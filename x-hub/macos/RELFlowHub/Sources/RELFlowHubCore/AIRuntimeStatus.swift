import Foundation

public enum AIRuntimeProviderReadinessState: String, Codable, Sendable {
    case ready
    case down
    case stale
}

public struct AIRuntimeProviderDiagnosis: Codable, Sendable, Equatable {
    public var provider: String
    public var state: AIRuntimeProviderReadinessState
    public var reasonCode: String
    public var runtimeVersion: String
    public var availableTaskKinds: [String]
    public var loadedModels: [String]
    public var deviceBackend: String
    public var importError: String
    public var loadedModelCount: Int
}

public enum AIRuntimeLocalCapabilityState: String, Codable, Sendable {
    case available
    case blocked
    case unavailable
    case stale
}

public struct AIRuntimeLocalCapabilityDiagnosis: Codable, Sendable, Equatable {
    public var capabilityKey: String
    public var title: String
    public var taskKinds: [String]
    public var state: AIRuntimeLocalCapabilityState
    public var providerIDs: [String]
    public var detail: String
}

public struct AIRuntimeProviderStatus: Codable, Sendable, Equatable {
    public var provider: String
    public var ok: Bool
    public var reasonCode: String?
    public var runtimeVersion: String?
    public var availableTaskKinds: [String]
    public var loadedModels: [String]
    public var deviceBackend: String?
    public var updatedAt: Double
    public var importError: String?
    public var activeMemoryBytes: Int64?
    public var peakMemoryBytes: Int64?
    public var loadedModelCount: Int?

    public init(
        provider: String,
        ok: Bool,
        reasonCode: String? = nil,
        runtimeVersion: String? = nil,
        availableTaskKinds: [String] = [],
        loadedModels: [String] = [],
        deviceBackend: String? = nil,
        updatedAt: Double = 0,
        importError: String? = nil,
        activeMemoryBytes: Int64? = nil,
        peakMemoryBytes: Int64? = nil,
        loadedModelCount: Int? = nil
    ) {
        self.provider = provider
        self.ok = ok
        self.reasonCode = reasonCode
        self.runtimeVersion = runtimeVersion
        self.availableTaskKinds = LocalModelCapabilityDefaults.normalizedStringList(
            availableTaskKinds,
            fallback: []
        )
        self.loadedModels = AIRuntimeProviderStatus.normalizedLoadedModels(loadedModels)
        self.deviceBackend = deviceBackend
        self.updatedAt = updatedAt
        self.importError = importError
        self.activeMemoryBytes = activeMemoryBytes
        self.peakMemoryBytes = peakMemoryBytes
        self.loadedModelCount = loadedModelCount
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case ok
        case reasonCode
        case runtimeVersion
        case availableTaskKinds
        case loadedModels
        case deviceBackend
        case updatedAt
        case importError
        case activeMemoryBytes
        case peakMemoryBytes
        case loadedModelCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = (try? c.decode(String.self, forKey: .provider)) ?? "unknown"
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        reasonCode = try? c.decodeIfPresent(String.self, forKey: .reasonCode)
        runtimeVersion = try? c.decodeIfPresent(String.self, forKey: .runtimeVersion)
        availableTaskKinds = LocalModelCapabilityDefaults.normalizedStringList(
            (try? c.decode([String].self, forKey: .availableTaskKinds)) ?? [],
            fallback: []
        )
        loadedModels = AIRuntimeProviderStatus.normalizedLoadedModels(
            (try? c.decode([String].self, forKey: .loadedModels)) ?? []
        )
        deviceBackend = try? c.decodeIfPresent(String.self, forKey: .deviceBackend)
        updatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? 0
        importError = try? c.decodeIfPresent(String.self, forKey: .importError)
        activeMemoryBytes = try? c.decodeIfPresent(Int64.self, forKey: .activeMemoryBytes)
        peakMemoryBytes = try? c.decodeIfPresent(Int64.self, forKey: .peakMemoryBytes)
        loadedModelCount = try? c.decodeIfPresent(Int.self, forKey: .loadedModelCount)
    }

    private static func normalizedLoadedModels(_ values: [String]) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for raw in values {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.isEmpty || seen.contains(token) {
                continue
            }
            seen.insert(token)
            out.append(token)
        }
        return out
    }
}

public struct AIRuntimeStatus: Codable, Sendable, Equatable {
    public var pid: Int
    public var updatedAt: Double
    public var schemaVersion: String?
    public var mlxOk: Bool
    public var runtimeVersion: String?
    public var importError: String?
    public var activeMemoryBytes: Int64?
    public var peakMemoryBytes: Int64?
    public var loadedModelCount: Int?
    public var providers: [String: AIRuntimeProviderStatus]

    public init(
        pid: Int,
        updatedAt: Double,
        mlxOk: Bool,
        runtimeVersion: String? = nil,
        importError: String? = nil,
        activeMemoryBytes: Int64? = nil,
        peakMemoryBytes: Int64? = nil,
        loadedModelCount: Int? = nil,
        schemaVersion: String? = nil,
        providers: [String: AIRuntimeProviderStatus] = [:]
    ) {
        self.pid = pid
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
        self.runtimeVersion = runtimeVersion
        self.importError = importError
        self.activeMemoryBytes = activeMemoryBytes
        self.peakMemoryBytes = peakMemoryBytes
        self.loadedModelCount = loadedModelCount
        let normalizedProviders = AIRuntimeStatus.normalizedProviders(
            providers,
            legacyPid: pid,
            legacyUpdatedAt: updatedAt,
            legacyMlxOk: mlxOk,
            legacyRuntimeVersion: runtimeVersion,
            legacyImportError: importError,
            legacyActiveMemoryBytes: activeMemoryBytes,
            legacyPeakMemoryBytes: peakMemoryBytes,
            legacyLoadedModelCount: loadedModelCount
        )
        self.providers = normalizedProviders
        self.mlxOk = normalizedProviders["mlx"]?.ok ?? mlxOk
    }

    enum CodingKeys: String, CodingKey {
        case pid
        case updatedAt
        case schemaVersion = "schema_version"
        case mlxOk
        case runtimeVersion
        case importError
        case activeMemoryBytes
        case peakMemoryBytes
        case loadedModelCount
        case providers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacyPid = (try? c.decode(Int.self, forKey: .pid)) ?? 0
        let legacyUpdatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? 0
        let legacyMlxOk = (try? c.decode(Bool.self, forKey: .mlxOk)) ?? false
        let legacyRuntimeVersion = try? c.decodeIfPresent(String.self, forKey: .runtimeVersion)
        let legacyImportError = try? c.decodeIfPresent(String.self, forKey: .importError)
        let legacyActiveMemoryBytes = try? c.decodeIfPresent(Int64.self, forKey: .activeMemoryBytes)
        let legacyPeakMemoryBytes = try? c.decodeIfPresent(Int64.self, forKey: .peakMemoryBytes)
        let legacyLoadedModelCount = try? c.decodeIfPresent(Int.self, forKey: .loadedModelCount)
        let decodedProviders = (try? c.decode([String: AIRuntimeProviderStatus].self, forKey: .providers)) ?? [:]

        pid = legacyPid
        updatedAt = legacyUpdatedAt
        schemaVersion = try? c.decodeIfPresent(String.self, forKey: .schemaVersion)
        providers = AIRuntimeStatus.normalizedProviders(
            decodedProviders,
            legacyPid: legacyPid,
            legacyUpdatedAt: legacyUpdatedAt,
            legacyMlxOk: legacyMlxOk,
            legacyRuntimeVersion: legacyRuntimeVersion,
            legacyImportError: legacyImportError,
            legacyActiveMemoryBytes: legacyActiveMemoryBytes,
            legacyPeakMemoryBytes: legacyPeakMemoryBytes,
            legacyLoadedModelCount: legacyLoadedModelCount
        )
        let mlxProvider = providers["mlx"]
        mlxOk = mlxProvider?.ok ?? legacyMlxOk
        runtimeVersion = legacyRuntimeVersion ?? mlxProvider?.runtimeVersion
        importError = legacyImportError ?? mlxProvider?.importError
        activeMemoryBytes = legacyActiveMemoryBytes ?? mlxProvider?.activeMemoryBytes
        peakMemoryBytes = legacyPeakMemoryBytes ?? mlxProvider?.peakMemoryBytes
        loadedModelCount = legacyLoadedModelCount ?? mlxProvider?.loadedModelCount
    }

    public func isAlive(ttl: Double = 3.0) -> Bool {
        (Date().timeIntervalSince1970 - updatedAt) < ttl
    }

    public func providerStatus(_ providerID: String) -> AIRuntimeProviderStatus? {
        providers[providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    public func isProviderReady(_ providerID: String, ttl: Double = 3.0) -> Bool {
        guard isAlive(ttl: ttl) else { return false }
        return providerStatus(providerID)?.ok ?? false
    }

    public func readyProviderIDs(ttl: Double = 3.0) -> [String] {
        guard isAlive(ttl: ttl) else { return [] }
        return providers.values
            .filter { $0.ok }
            .map(\.provider)
            .sorted()
    }

    public func hasReadyProvider(ttl: Double = 3.0) -> Bool {
        !readyProviderIDs(ttl: ttl).isEmpty
    }

    public func providerSummary(ttl: Double = 3.0) -> String {
        let ready = readyProviderIDs(ttl: ttl)
        return ready.isEmpty ? "none" : ready.joined(separator: ",")
    }

    public func providerDiagnoses(ttl: Double = 3.0) -> [AIRuntimeProviderDiagnosis] {
        let runtimeAlive = isAlive(ttl: ttl)
        return providers.keys.sorted().compactMap { key in
            guard let status = providers[key] else { return nil }
            return AIRuntimeProviderDiagnosis(
                provider: key,
                state: runtimeAlive ? (status.ok ? .ready : .down) : .stale,
                reasonCode: (status.reasonCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                runtimeVersion: (status.runtimeVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                availableTaskKinds: LocalModelCapabilityDefaults.normalizedStringList(
                    status.availableTaskKinds,
                    fallback: []
                ),
                loadedModels: status.loadedModels,
                deviceBackend: (status.deviceBackend ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                importError: (status.importError ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                loadedModelCount: status.loadedModelCount ?? status.loadedModels.count
            )
        }
    }

    public func localCapabilityDiagnoses(
        ttl: Double = 3.0,
        blockedCapabilities: [String] = []
    ) -> [AIRuntimeLocalCapabilityDiagnosis] {
        let runtimeAlive = isAlive(ttl: ttl)
        let providerDiagnoses = providerDiagnoses(ttl: ttl)
        let blocked = Set(
            blockedCapabilities
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        return AIRuntimeStatus.localCapabilitySpecs.map { spec in
            if blocked.contains(spec.capabilityKey) {
                return AIRuntimeLocalCapabilityDiagnosis(
                    capabilityKey: spec.capabilityKey,
                    title: spec.title,
                    taskKinds: spec.taskKinds,
                    state: .blocked,
                    providerIDs: [],
                    detail: "blocked by \(spec.capabilityKey)"
                )
            }

            if !runtimeAlive {
                return AIRuntimeLocalCapabilityDiagnosis(
                    capabilityKey: spec.capabilityKey,
                    title: spec.title,
                    taskKinds: spec.taskKinds,
                    state: .stale,
                    providerIDs: [],
                    detail: "runtime heartbeat stale"
                )
            }

            let ready = providerDiagnoses.filter { diagnosis in
                diagnosis.state == .ready && AIRuntimeStatus.providerDiagnosis(diagnosis, supportsAnyTaskIn: spec.taskKinds)
            }
            if !ready.isEmpty {
                let providers = ready.map(\.provider)
                return AIRuntimeLocalCapabilityDiagnosis(
                    capabilityKey: spec.capabilityKey,
                    title: spec.title,
                    taskKinds: spec.taskKinds,
                    state: .available,
                    providerIDs: providers,
                    detail: "available via \(providers.joined(separator: ", "))"
                )
            }

            let candidates = AIRuntimeStatus.candidateProviderDiagnoses(
                for: spec,
                providerDiagnoses: providerDiagnoses
            )
            let detail: String
            let providerIDs = candidates.map(\.provider)
            if candidates.isEmpty {
                detail = "no provider advertises \(spec.taskKinds.joined(separator: "/"))"
            } else {
                detail = candidates
                    .map { AIRuntimeStatus.candidateProviderDetail($0, taskKinds: spec.taskKinds) }
                    .joined(separator: "; ")
            }

            return AIRuntimeLocalCapabilityDiagnosis(
                capabilityKey: spec.capabilityKey,
                title: spec.title,
                taskKinds: spec.taskKinds,
                state: .unavailable,
                providerIDs: providerIDs,
                detail: detail
            )
        }
    }

    public func providerOperatorSummary(
        ttl: Double = 3.0,
        blockedCapabilities: [String] = []
    ) -> String {
        let runtimeAlive = isAlive(ttl: ttl)
        let diagnoses = providerDiagnoses(ttl: ttl)
        let capabilities = localCapabilityDiagnoses(ttl: ttl, blockedCapabilities: blockedCapabilities)

        var lines: [String] = []
        lines.append("runtime_alive=\(runtimeAlive ? "1" : "0")")
        lines.append("runtime_pid=\(pid)")
        if let schemaVersion, !schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("schema_version=\(schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let readyProviders = diagnoses.filter { $0.state == .ready }.map(\.provider)
        lines.append("ready_providers=\(readyProviders.isEmpty ? "none" : readyProviders.joined(separator: ","))")
        lines.append("providers:")
        for diagnosis in diagnoses {
            lines.append(AIRuntimeStatus.providerDiagnosisLine(diagnosis))
        }
        lines.append("capabilities:")
        for capability in capabilities {
            let providers = capability.providerIDs.isEmpty ? "none" : capability.providerIDs.joined(separator: ",")
            lines.append(
                "capability=\(capability.capabilityKey) state=\(capability.state.rawValue) providers=\(providers) detail=\(capability.detail)"
            )
        }
        return lines.joined(separator: "\n")
    }

    public func providerDoctorText(
        ttl: Double = 3.0,
        blockedCapabilities: [String] = []
    ) -> String {
        let diagnoses = providerDiagnoses(ttl: ttl)
        let capabilities = localCapabilityDiagnoses(ttl: ttl, blockedCapabilities: blockedCapabilities)
        let readyProviders = diagnoses.filter { $0.state == .ready }.map(\.provider)
        let downProviders = diagnoses.filter { $0.state == .down }

        var parts: [String] = []
        if !isAlive(ttl: ttl) {
            parts.append("Local runtime heartbeat is stale. No provider is currently considered ready.")
        } else if readyProviders.isEmpty {
            parts.append("No local provider is ready.")
        } else if downProviders.isEmpty {
            parts.append("Local runtime is fully ready: \(readyProviders.joined(separator: ", ")).")
        } else {
            let downSummary = downProviders
                .map { AIRuntimeStatus.doctorProviderClause($0) }
                .joined(separator: "; ")
            parts.append(
                "Local runtime is partially ready: \(readyProviders.joined(separator: ", ")) ready; \(downSummary)."
            )
        }

        for capability in capabilities {
            switch capability.capabilityKey {
            case "ai.generate.local":
                if capability.state != .available {
                    parts.append("Text generation is unavailable: \(capability.detail).")
                }
            case "ai.embed.local":
                if capability.state == .available {
                    parts.append("Embeddings are available via \(capability.providerIDs.joined(separator: ", ")).")
                } else if capability.state == .blocked {
                    parts.append("Embeddings are blocked by \(capability.capabilityKey).")
                }
            case "ai.audio.local":
                if capability.state == .blocked {
                    parts.append("Local audio is blocked by \(capability.capabilityKey).")
                } else if capability.state == .available {
                    parts.append("Local audio is available via \(capability.providerIDs.joined(separator: ", ")).")
                } else {
                    parts.append("Local audio is unavailable: \(capability.detail).")
                }
            case "ai.vision.local":
                if capability.state == .blocked {
                    parts.append("Local vision is blocked by \(capability.capabilityKey).")
                }
            default:
                break
            }
        }

        return parts.joined(separator: " ")
    }

    private struct LocalCapabilitySpec {
        var capabilityKey: String
        var title: String
        var taskKinds: [String]
        var fallbackProviderIDs: [String]
    }

    private static let localCapabilitySpecs: [LocalCapabilitySpec] = [
        LocalCapabilitySpec(
            capabilityKey: "ai.generate.local",
            title: "Local text generation",
            taskKinds: ["text_generate"],
            fallbackProviderIDs: ["mlx"]
        ),
        LocalCapabilitySpec(
            capabilityKey: "ai.embed.local",
            title: "Local embeddings",
            taskKinds: ["embedding"],
            fallbackProviderIDs: ["transformers"]
        ),
        LocalCapabilitySpec(
            capabilityKey: "ai.audio.local",
            title: "Local audio",
            taskKinds: ["speech_to_text"],
            fallbackProviderIDs: ["transformers"]
        ),
        LocalCapabilitySpec(
            capabilityKey: "ai.vision.local",
            title: "Local vision",
            taskKinds: ["vision_understand", "ocr"],
            fallbackProviderIDs: ["transformers"]
        ),
    ]

    private static func providerDiagnosis(
        _ diagnosis: AIRuntimeProviderDiagnosis,
        supportsAnyTaskIn taskKinds: [String]
    ) -> Bool {
        !Set(diagnosis.availableTaskKinds).isDisjoint(with: Set(taskKinds))
    }

    private static func candidateProviderDiagnoses(
        for spec: LocalCapabilitySpec,
        providerDiagnoses: [AIRuntimeProviderDiagnosis]
    ) -> [AIRuntimeProviderDiagnosis] {
        let advertised = providerDiagnoses.filter { diagnosis in
            providerDiagnosis(diagnosis, supportsAnyTaskIn: spec.taskKinds)
        }
        if !advertised.isEmpty {
            return advertised
        }
        return providerDiagnoses.filter { diagnosis in
            spec.fallbackProviderIDs.contains(diagnosis.provider)
        }
    }

    private static func candidateProviderDetail(
        _ diagnosis: AIRuntimeProviderDiagnosis,
        taskKinds: [String]
    ) -> String {
        switch diagnosis.state {
        case .ready:
            let tasks = diagnosis.availableTaskKinds.isEmpty ? "(none)" : diagnosis.availableTaskKinds.joined(separator: ",")
            return "\(diagnosis.provider) ready(tasks=\(tasks))"
        case .down:
            if !diagnosis.reasonCode.isEmpty {
                return "\(diagnosis.provider) down(\(diagnosis.reasonCode))"
            }
            if !diagnosis.importError.isEmpty {
                return "\(diagnosis.provider) down(import_error)"
            }
            return "\(diagnosis.provider) down"
        case .stale:
            return "\(diagnosis.provider) stale"
        }
    }

    private static func providerDiagnosisLine(_ diagnosis: AIRuntimeProviderDiagnosis) -> String {
        let reason = diagnosis.reasonCode.isEmpty ? "none" : diagnosis.reasonCode
        let runtimeVersion = diagnosis.runtimeVersion.isEmpty ? "unknown" : diagnosis.runtimeVersion
        let tasks = diagnosis.availableTaskKinds.isEmpty ? "(none)" : diagnosis.availableTaskKinds.joined(separator: ",")
        let models = diagnosis.loadedModels.isEmpty ? "(none)" : diagnosis.loadedModels.joined(separator: ",")
        let backend = diagnosis.deviceBackend.isEmpty ? "unknown" : diagnosis.deviceBackend
        let importError = diagnosis.importError.isEmpty ? "" : " import_error=\(diagnosis.importError)"
        return "provider=\(diagnosis.provider) state=\(diagnosis.state.rawValue) reason=\(reason) runtime_version=\(runtimeVersion) device_backend=\(backend) tasks=\(tasks) loaded_models=\(models) loaded_model_count=\(diagnosis.loadedModelCount)\(importError)"
    }

    private static func doctorProviderClause(_ diagnosis: AIRuntimeProviderDiagnosis) -> String {
        if !diagnosis.reasonCode.isEmpty {
            return "\(diagnosis.provider) unavailable (\(diagnosis.reasonCode))"
        }
        if !diagnosis.importError.isEmpty {
            return "\(diagnosis.provider) unavailable (import_error)"
        }
        return "\(diagnosis.provider) unavailable"
    }

    private static func normalizedProviders(
        _ rawProviders: [String: AIRuntimeProviderStatus],
        legacyPid: Int,
        legacyUpdatedAt: Double,
        legacyMlxOk: Bool,
        legacyRuntimeVersion: String?,
        legacyImportError: String?,
        legacyActiveMemoryBytes: Int64?,
        legacyPeakMemoryBytes: Int64?,
        legacyLoadedModelCount: Int?
    ) -> [String: AIRuntimeProviderStatus] {
        var out: [String: AIRuntimeProviderStatus] = [:]
        for (rawKey, rawValue) in rawProviders {
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let provider = rawValue.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedProvider = provider.isEmpty ? key : provider
            out[key] = AIRuntimeProviderStatus(
                provider: normalizedProvider,
                ok: rawValue.ok,
                reasonCode: rawValue.reasonCode,
                runtimeVersion: rawValue.runtimeVersion,
                availableTaskKinds: rawValue.availableTaskKinds,
                loadedModels: rawValue.loadedModels,
                deviceBackend: rawValue.deviceBackend,
                updatedAt: rawValue.updatedAt == 0 ? legacyUpdatedAt : rawValue.updatedAt,
                importError: rawValue.importError,
                activeMemoryBytes: rawValue.activeMemoryBytes,
                peakMemoryBytes: rawValue.peakMemoryBytes,
                loadedModelCount: rawValue.loadedModelCount
            )
        }

        if out["mlx"] == nil {
            out["mlx"] = AIRuntimeProviderStatus(
                provider: "mlx",
                ok: legacyMlxOk,
                reasonCode: legacyMlxOk ? "legacy_ready" : "legacy_unavailable",
                runtimeVersion: legacyRuntimeVersion,
                availableTaskKinds: legacyMlxOk ? ["text_generate"] : [],
                loadedModels: [],
                deviceBackend: "mps",
                updatedAt: legacyUpdatedAt,
                importError: legacyImportError,
                activeMemoryBytes: legacyActiveMemoryBytes,
                peakMemoryBytes: legacyPeakMemoryBytes,
                loadedModelCount: legacyLoadedModelCount
            )
        }

        return out
    }
}

public enum AIRuntimeStatusStorage {
    public static let fileName = "ai_runtime_status.json"

    public static func url() -> URL {
        if let g = SharedPaths.appGroupDirectory() {
            return g.appendingPathComponent(fileName)
        }
        return SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    public static func load() -> AIRuntimeStatus? {
        let url = url()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AIRuntimeStatus.self, from: data)
    }
}
