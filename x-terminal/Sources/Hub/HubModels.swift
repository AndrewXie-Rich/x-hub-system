import Foundation

private enum AIRuntimeJSON {
    static func object(_ value: Any?) -> [String: Any] {
        value as? [String: Any] ?? [:]
    }

    static func array(_ value: Any?) -> [Any] {
        value as? [Any] ?? []
    }

    static func string(_ value: Any?) -> String {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func lowercasedString(_ value: Any?) -> String {
        string(value).lowercased()
    }

    static func int(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? Int64 {
            return Int(value)
        }
        if let value = value as? Double, value.isFinite {
            return Int(value)
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        let token = string(value)
        guard !token.isEmpty, let parsed = Int(token) else {
            return nil
        }
        return parsed
    }

    static func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 {
            return value
        }
        if let value = value as? Int {
            return Int64(value)
        }
        if let value = value as? Double, value.isFinite {
            return Int64(value)
        }
        if let value = value as? NSNumber {
            return value.int64Value
        }
        let token = string(value)
        guard !token.isEmpty, let parsed = Int64(token) else {
            return nil
        }
        return parsed
    }

    static func double(_ value: Any?) -> Double? {
        if let value = value as? Double, value.isFinite {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        if let value = value as? Int64 {
            return Double(value)
        }
        if let value = value as? NSNumber {
            let number = value.doubleValue
            return number.isFinite ? number : nil
        }
        let token = string(value)
        guard !token.isEmpty, let parsed = Double(token), parsed.isFinite else {
            return nil
        }
        return parsed
    }

    static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        switch lowercasedString(value) {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }

    static func stringList(_ value: Any?) -> [String] {
        let rawItems: [Any]
        if let array = value as? [Any] {
            rawItems = array
        } else if let token = value {
            rawItems = [token]
        } else {
            rawItems = []
        }

        var out: [String] = []
        var seen = Set<String>()
        for raw in rawItems {
            let token = string(raw).lowercased()
            guard !token.isEmpty, seen.insert(token).inserted else { continue }
            out.append(token)
        }
        return out
    }

    static func decodeLoadProfile(from value: Any?) -> HubLocalModelLoadProfile? {
        let object = object(value)
        guard !object.isEmpty,
              JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        return try? JSONDecoder().decode(HubLocalModelLoadProfile.self, from: data)
    }
}

struct AIRuntimeProviderPackStatus: Equatable {
    var providerID: String
    var engine: String
    var version: String
    var installed: Bool
    var enabled: Bool
    var packState: String
    var reasonCode: String

    init(jsonObject: [String: Any]) {
        providerID = AIRuntimeJSON.lowercasedString(jsonObject["providerId"] ?? jsonObject["provider_id"])
        engine = AIRuntimeJSON.string(jsonObject["engine"])
        version = AIRuntimeJSON.string(jsonObject["version"])
        installed = AIRuntimeJSON.bool(jsonObject["installed"]) ?? false
        enabled = AIRuntimeJSON.bool(jsonObject["enabled"]) ?? false
        packState = AIRuntimeJSON.lowercasedString(jsonObject["packState"] ?? jsonObject["pack_state"])
        reasonCode = AIRuntimeJSON.string(jsonObject["reasonCode"] ?? jsonObject["reason_code"])
    }
}

enum HubModelRemoteIdentityComponentKind: String, Equatable {
    case keyReference
    case endpointHost
    case providerModelID
}

struct HubModelRemoteIdentityComponent: Equatable {
    let kind: HubModelRemoteIdentityComponentKind
    let value: String
}

struct AIRuntimeLoadedInstance: Equatable {
    var providerID: String
    var instanceKey: String
    var modelID: String
    var taskKinds: [String]
    var loadProfileHash: String
    var effectiveContextLength: Int?
    var maxContextLength: Int?
    var effectiveLoadProfile: HubLocalModelLoadProfile?
    var residencyScope: String?
    var deviceBackend: String?

    init(jsonObject: [String: Any], fallbackProviderID: String = "") {
        providerID = AIRuntimeJSON.lowercasedString(
            jsonObject["provider"] ?? fallbackProviderID
        )
        instanceKey = AIRuntimeJSON.string(jsonObject["instanceKey"] ?? jsonObject["instance_key"])
        modelID = AIRuntimeJSON.string(jsonObject["modelId"] ?? jsonObject["model_id"])
        taskKinds = AIRuntimeJSON.stringList(jsonObject["taskKinds"] ?? jsonObject["task_kinds"])
        loadProfileHash = AIRuntimeJSON.string(
            jsonObject["loadProfileHash"]
                ?? jsonObject["load_profile_hash"]
                ?? jsonObject["loadConfigHash"]
                ?? jsonObject["load_config_hash"]
        )
        effectiveContextLength = AIRuntimeJSON.int(
            jsonObject["effectiveContextLength"]
                ?? jsonObject["effective_context_length"]
                ?? jsonObject["currentContextLength"]
                ?? jsonObject["current_context_length"]
        )
        maxContextLength = AIRuntimeJSON.int(
            jsonObject["maxContextLength"] ?? jsonObject["max_context_length"]
        )
        effectiveLoadProfile = AIRuntimeJSON.decodeLoadProfile(
            from: jsonObject["effectiveLoadProfile"]
                ?? jsonObject["effective_load_profile"]
                ?? jsonObject["loadConfig"]
                ?? jsonObject["load_config"]
        )
        let resolvedResidencyScope = AIRuntimeJSON.string(
            jsonObject["residencyScope"] ?? jsonObject["residency_scope"]
        )
        residencyScope = resolvedResidencyScope.isEmpty ? nil : resolvedResidencyScope
        let resolvedDeviceBackend = AIRuntimeJSON.string(
            jsonObject["deviceBackend"] ?? jsonObject["device_backend"]
        )
        deviceBackend = resolvedDeviceBackend.isEmpty ? nil : resolvedDeviceBackend
    }
}

struct AIRuntimeProviderStatus: Equatable {
    var providerID: String
    var ok: Bool
    var reasonCode: String
    var runtimeVersion: String?
    var importError: String?
    var runtimeSource: String?
    var runtimeSourcePath: String?
    var runtimeResolutionState: String?
    var runtimeReasonCode: String?
    var fallbackUsed: Bool
    var runtimeHint: String?
    var availableTaskKinds: [String]
    var realTaskKinds: [String]
    var fallbackTaskKinds: [String]
    var unavailableTaskKinds: [String]
    var supportedLifecycleActions: [String]
    var warmupTaskKinds: [String]
    var packID: String?
    var packEngine: String?
    var packVersion: String?
    var packInstalled: Bool?
    var packEnabled: Bool?
    var packState: String?
    var packReasonCode: String?
    var loadedInstances: [AIRuntimeLoadedInstance]

    init(providerIDHint: String, jsonObject: [String: Any]) {
        let normalizedProviderID = AIRuntimeJSON.lowercasedString(
            jsonObject["provider"] ?? providerIDHint
        )
        providerID = normalizedProviderID.isEmpty
            ? AIRuntimeJSON.lowercasedString(providerIDHint)
            : normalizedProviderID
        ok = AIRuntimeJSON.bool(jsonObject["ok"]) ?? false
        reasonCode = AIRuntimeJSON.string(jsonObject["reasonCode"] ?? jsonObject["reason_code"])
        let resolvedRuntimeVersion = AIRuntimeJSON.string(
            jsonObject["runtimeVersion"] ?? jsonObject["runtime_version"]
        )
        runtimeVersion = resolvedRuntimeVersion.isEmpty ? nil : resolvedRuntimeVersion
        let resolvedImportError = AIRuntimeJSON.string(
            jsonObject["importError"] ?? jsonObject["import_error"]
        )
        importError = resolvedImportError.isEmpty ? nil : resolvedImportError
        let resolvedRuntimeSource = AIRuntimeJSON.lowercasedString(
            jsonObject["runtimeSource"] ?? jsonObject["runtime_source"]
        )
        runtimeSource = resolvedRuntimeSource.isEmpty ? nil : resolvedRuntimeSource
        let resolvedRuntimeSourcePath = AIRuntimeJSON.string(
            jsonObject["runtimeSourcePath"] ?? jsonObject["runtime_source_path"]
        )
        runtimeSourcePath = resolvedRuntimeSourcePath.isEmpty ? nil : resolvedRuntimeSourcePath
        let resolvedRuntimeResolutionState = AIRuntimeJSON.lowercasedString(
            jsonObject["runtimeResolutionState"] ?? jsonObject["runtime_resolution_state"]
        )
        runtimeResolutionState = resolvedRuntimeResolutionState.isEmpty ? nil : resolvedRuntimeResolutionState
        let resolvedRuntimeReasonCode = AIRuntimeJSON.string(
            jsonObject["runtimeReasonCode"] ?? jsonObject["runtime_reason_code"]
        )
        runtimeReasonCode = resolvedRuntimeReasonCode.isEmpty ? nil : resolvedRuntimeReasonCode
        fallbackUsed = AIRuntimeJSON.bool(
            jsonObject["fallbackUsed"] ?? jsonObject["fallback_used"]
        ) ?? false
        let resolvedRuntimeHint = AIRuntimeJSON.string(
            jsonObject["runtimeHint"] ?? jsonObject["runtime_hint"]
        )
        runtimeHint = resolvedRuntimeHint.isEmpty ? nil : resolvedRuntimeHint
        availableTaskKinds = AIRuntimeJSON.stringList(
            jsonObject["availableTaskKinds"] ?? jsonObject["available_task_kinds"]
        )
        realTaskKinds = AIRuntimeJSON.stringList(
            jsonObject["realTaskKinds"] ?? jsonObject["real_task_kinds"]
        )
        fallbackTaskKinds = AIRuntimeJSON.stringList(
            jsonObject["fallbackTaskKinds"] ?? jsonObject["fallback_task_kinds"]
        )
        unavailableTaskKinds = AIRuntimeJSON.stringList(
            jsonObject["unavailableTaskKinds"] ?? jsonObject["unavailable_task_kinds"]
        )
        supportedLifecycleActions = AIRuntimeJSON.stringList(
            jsonObject["supportedLifecycleActions"] ?? jsonObject["supported_lifecycle_actions"]
        )
        warmupTaskKinds = AIRuntimeJSON.stringList(
            jsonObject["warmupTaskKinds"] ?? jsonObject["warmup_task_kinds"]
        )
        let resolvedPackID = AIRuntimeJSON.lowercasedString(
            jsonObject["packId"] ?? jsonObject["pack_id"]
        )
        packID = resolvedPackID.isEmpty ? nil : resolvedPackID
        let resolvedPackEngine = AIRuntimeJSON.string(
            jsonObject["packEngine"] ?? jsonObject["pack_engine"]
        )
        packEngine = resolvedPackEngine.isEmpty ? nil : resolvedPackEngine
        let resolvedPackVersion = AIRuntimeJSON.string(
            jsonObject["packVersion"] ?? jsonObject["pack_version"]
        )
        packVersion = resolvedPackVersion.isEmpty ? nil : resolvedPackVersion
        packInstalled = AIRuntimeJSON.bool(jsonObject["packInstalled"] ?? jsonObject["pack_installed"])
        packEnabled = AIRuntimeJSON.bool(jsonObject["packEnabled"] ?? jsonObject["pack_enabled"])
        let resolvedPackState = AIRuntimeJSON.lowercasedString(
            jsonObject["packState"] ?? jsonObject["pack_state"]
        )
        packState = resolvedPackState.isEmpty ? nil : resolvedPackState
        let resolvedPackReasonCode = AIRuntimeJSON.string(
            jsonObject["packReasonCode"] ?? jsonObject["pack_reason_code"]
        )
        packReasonCode = resolvedPackReasonCode.isEmpty ? nil : resolvedPackReasonCode
        let fallbackProviderID = providerID
        loadedInstances = AIRuntimeJSON.array(
            jsonObject["loadedInstances"] ?? jsonObject["loaded_instances"]
        ).compactMap { raw -> AIRuntimeLoadedInstance? in
            let object = AIRuntimeJSON.object(raw)
            guard !object.isEmpty else { return nil }
            return AIRuntimeLoadedInstance(
                jsonObject: object,
                fallbackProviderID: fallbackProviderID
            )
        }
    }
}

struct AIRuntimeStatus: Equatable {
    var pid: Int
    var updatedAt: Double
    var mlxOk: Bool
    var runtimeVersion: String?
    var importError: String?
    var activeMemoryBytes: Int64?
    var peakMemoryBytes: Int64?
    var loadedModelCount: Int?
    var schemaVersion: String?
    var localRuntimeEntryVersion: String?
    var runtimeAlive: Bool?
    var providerIDs: [String]
    var readyProviderIDs: [String]
    var providerPacks: [AIRuntimeProviderPackStatus]
    var providers: [String: AIRuntimeProviderStatus]
    var loadedInstances: [AIRuntimeLoadedInstance]
    var loadedInstanceCount: Int?

    init(
        pid: Int = 0,
        updatedAt: Double = 0,
        mlxOk: Bool = false,
        runtimeVersion: String? = nil,
        importError: String? = nil,
        activeMemoryBytes: Int64? = nil,
        peakMemoryBytes: Int64? = nil,
        loadedModelCount: Int? = nil,
        schemaVersion: String? = nil,
        localRuntimeEntryVersion: String? = nil,
        runtimeAlive: Bool? = nil,
        providerIDs: [String] = [],
        readyProviderIDs: [String] = [],
        providerPacks: [AIRuntimeProviderPackStatus] = [],
        providers: [String: AIRuntimeProviderStatus] = [:],
        loadedInstances: [AIRuntimeLoadedInstance] = [],
        loadedInstanceCount: Int? = nil
    ) {
        self.pid = pid
        self.updatedAt = updatedAt
        self.mlxOk = mlxOk
        self.runtimeVersion = runtimeVersion
        self.importError = importError
        self.activeMemoryBytes = activeMemoryBytes
        self.peakMemoryBytes = peakMemoryBytes
        self.loadedModelCount = loadedModelCount
        self.schemaVersion = schemaVersion
        self.localRuntimeEntryVersion = localRuntimeEntryVersion
        self.runtimeAlive = runtimeAlive
        self.providerIDs = providerIDs
        self.readyProviderIDs = readyProviderIDs
        self.providerPacks = providerPacks
        self.providers = providers
        self.loadedInstances = loadedInstances
        self.loadedInstanceCount = loadedInstanceCount
    }

    func isAlive(ttl: Double = 3.0) -> Bool {
        let heartbeatFresh = (Date().timeIntervalSince1970 - updatedAt) < ttl
        if let runtimeAlive {
            return runtimeAlive && heartbeatFresh
        }
        return heartbeatFresh
    }

    var normalizedProviderIDs: [String] {
        var values = Set(providerIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        values.formUnion(providers.keys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        values.formUnion(providerPacks.map(\.providerID))
        values.formUnion(readyProviderIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        if values.isEmpty, mlxOk || importError != nil || runtimeVersion != nil {
            values.insert("mlx")
        }
        return values.sorted()
    }

    var normalizedReadyProviderIDs: [String] {
        let explicit = Set(readyProviderIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let derived = Set(
            providers.values
                .filter(\.ok)
                .map(\.providerID)
        )
        let merged = explicit.union(derived)
        if !merged.isEmpty {
            return merged.sorted()
        }
        if providers.isEmpty, mlxOk {
            return ["mlx"]
        }
        return []
    }

    var providerCount: Int {
        normalizedProviderIDs.count
    }

    var readyProviderCount: Int {
        normalizedReadyProviderIDs.count
    }

    var hasProviderInventory: Bool {
        providerCount > 0
    }

    var hasAnyReadyProvider: Bool {
        readyProviderCount > 0
    }

    var hasPartialReadyProviders: Bool {
        let total = providerCount
        return total > 0 && readyProviderCount > 0 && readyProviderCount < total
    }

    var hasNoReadyProviders: Bool {
        let total = providerCount
        return total > 0 && readyProviderCount == 0
    }

    var effectiveLoadedInstanceCount: Int {
        max(loadedInstanceCount ?? 0, loadedInstances.count)
    }

    func providerReadinessStateCode(ttl: Double = 3.0) -> String? {
        guard hasProviderInventory else { return nil }
        if !isAlive(ttl: ttl) {
            return "runtime_heartbeat_stale"
        }
        if hasNoReadyProviders {
            return "no_ready_provider"
        }
        if hasPartialReadyProviders {
            return "provider_partial_readiness"
        }
        return "provider_ready"
    }

    var providerReadinessSummary: String? {
        let total = providerCount
        guard total > 0 else { return nil }
        let ready = normalizedReadyProviderIDs
        if ready.isEmpty {
            return "provider 就绪 0/\(total)"
        }
        return "provider 就绪 \(ready.count)/\(total)：\(ready.joined(separator: ", "))"
    }

    var loadedInstanceDisplaySummary: String? {
        let count = effectiveLoadedInstanceCount
        guard count > 0 else { return nil }
        if let first = loadedInstances.first {
            let provider = first.providerID.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelID = first.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            if count == 1, !provider.isEmpty, !modelID.isEmpty {
                return "已加载实例 1 个：\(provider) / \(modelID)"
            }
        }
        return "已加载实例 \(count) 个"
    }

    func providerReadinessDetailLines(ttl: Double = 3.0) -> [String] {
        var detailLines: [String] = []
        if let stateCode = providerReadinessStateCode(ttl: ttl) {
            detailLines.append("runtime_provider_state=\(stateCode)")
            detailLines.append("ready_providers=\(normalizedReadyProviderIDs.isEmpty ? "none" : normalizedReadyProviderIDs.joined(separator: ","))")
            detailLines.append("ready_provider_count=\(readyProviderCount)")
            detailLines.append("provider_count=\(providerCount)")
        }
        if effectiveLoadedInstanceCount > 0 {
            detailLines.append("loaded_instances=\(effectiveLoadedInstanceCount)")
        }
        if let firstUnavailableProviderSummary {
            detailLines.append("runtime_provider_issue=\(firstUnavailableProviderSummary)")
        }
        return orderedUniqueDetailLines(detailLines)
    }

    var firstUnavailableProviderSummary: String? {
        let ready = Set(normalizedReadyProviderIDs)
        let unavailable = normalizedProviderIDs.compactMap { providerID -> String? in
            guard !ready.contains(providerID) else { return nil }
            guard let status = providers[providerID] else {
                return providerID
            }
            let reason = status.reasonCode
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if reason.isEmpty {
                return providerID
            }
            return "\(providerID): \(reason)"
        }
        return unavailable.first
    }

    private func orderedUniqueDetailLines(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            output.append(normalized)
        }
        return output
    }

    static func load(from url: URL) -> AIRuntimeStatus? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(from: data)
    }

    static func decode(from data: Data) -> AIRuntimeStatus? {
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let object = raw as? [String: Any] else {
            return nil
        }
        return AIRuntimeStatus(jsonObject: object)
    }

    private init(jsonObject: [String: Any]) {
        pid = AIRuntimeJSON.int(jsonObject["pid"]) ?? 0
        updatedAt = AIRuntimeJSON.double(
            jsonObject["updatedAt"] ?? jsonObject["updated_at"]
        ) ?? 0
        mlxOk = AIRuntimeJSON.bool(jsonObject["mlxOk"] ?? jsonObject["mlx_ok"]) ?? false
        let resolvedRuntimeVersion = AIRuntimeJSON.string(
            jsonObject["runtimeVersion"] ?? jsonObject["runtime_version"]
        )
        runtimeVersion = resolvedRuntimeVersion.isEmpty ? nil : resolvedRuntimeVersion
        let resolvedImportError = AIRuntimeJSON.string(
            jsonObject["importError"] ?? jsonObject["import_error"]
        )
        importError = resolvedImportError.isEmpty ? nil : resolvedImportError
        activeMemoryBytes = AIRuntimeJSON.int64(
            jsonObject["activeMemoryBytes"] ?? jsonObject["active_memory_bytes"]
        )
        peakMemoryBytes = AIRuntimeJSON.int64(
            jsonObject["peakMemoryBytes"] ?? jsonObject["peak_memory_bytes"]
        )
        loadedModelCount = AIRuntimeJSON.int(
            jsonObject["loadedModelCount"] ?? jsonObject["loaded_model_count"]
        )
        let resolvedSchemaVersion = AIRuntimeJSON.string(
            jsonObject["schemaVersion"] ?? jsonObject["schema_version"]
        )
        schemaVersion = resolvedSchemaVersion.isEmpty ? nil : resolvedSchemaVersion
        let resolvedLocalRuntimeEntryVersion = AIRuntimeJSON.string(
            jsonObject["localRuntimeEntryVersion"] ?? jsonObject["local_runtime_entry_version"]
        )
        localRuntimeEntryVersion = resolvedLocalRuntimeEntryVersion.isEmpty ? nil : resolvedLocalRuntimeEntryVersion
        runtimeAlive = AIRuntimeJSON.bool(
            jsonObject["runtimeAlive"] ?? jsonObject["runtime_alive"]
        )
        providerIDs = AIRuntimeJSON.stringList(
            jsonObject["providerIds"] ?? jsonObject["provider_ids"]
        )
        readyProviderIDs = AIRuntimeJSON.stringList(
            jsonObject["readyProviderIds"] ?? jsonObject["ready_provider_ids"]
        )
        let decodedProviderPacks: [AIRuntimeProviderPackStatus] = AIRuntimeJSON.array(
            jsonObject["providerPacks"] ?? jsonObject["provider_packs"]
        ).compactMap { raw -> AIRuntimeProviderPackStatus? in
            let object = AIRuntimeJSON.object(raw)
            guard !object.isEmpty else { return nil }
            return AIRuntimeProviderPackStatus(jsonObject: object)
        }
        providerPacks = decodedProviderPacks

        let rawProviders = AIRuntimeJSON.object(jsonObject["providers"])
        var normalizedProviders: [String: AIRuntimeProviderStatus] = [:]
        for (rawProviderID, rawStatus) in rawProviders {
            let object = AIRuntimeJSON.object(rawStatus)
            guard !object.isEmpty else { continue }
            let status = AIRuntimeProviderStatus(providerIDHint: rawProviderID, jsonObject: object)
            let providerID = status.providerID.isEmpty
                ? rawProviderID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                : status.providerID
            normalizedProviders[providerID] = status
        }
        providers = normalizedProviders

        let decodedLoadedInstances: [AIRuntimeLoadedInstance] = AIRuntimeJSON.array(
            jsonObject["loadedInstances"] ?? jsonObject["loaded_instances"]
        ).compactMap { raw -> AIRuntimeLoadedInstance? in
            let object = AIRuntimeJSON.object(raw)
            guard !object.isEmpty else { return nil }
            return AIRuntimeLoadedInstance(jsonObject: object)
        }
        loadedInstances = decodedLoadedInstances
        loadedInstanceCount = AIRuntimeJSON.int(
            jsonObject["loadedInstanceCount"] ?? jsonObject["loaded_instance_count"]
        )
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
    var remoteConfiguredContextLength: Int?
    var remoteKnownContextLength: Int?
    var remoteKnownContextSource: String?
    var remoteGroupDisplayName: String?
    var remoteProviderModelID: String?
    var remoteKeyReference: String?
    var remoteEndpointHost: String?

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
        processorRequirements: HubModelProcessorRequirements? = nil,
        remoteConfiguredContextLength: Int? = nil,
        remoteKnownContextLength: Int? = nil,
        remoteKnownContextSource: String? = nil,
        remoteGroupDisplayName: String? = nil,
        remoteProviderModelID: String? = nil,
        remoteKeyReference: String? = nil,
        remoteEndpointHost: String? = nil
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
        if let remoteConfiguredContextLength, remoteConfiguredContextLength > 0 {
            self.remoteConfiguredContextLength = max(512, remoteConfiguredContextLength)
        } else {
            self.remoteConfiguredContextLength = nil
        }
        if let remoteKnownContextLength, remoteKnownContextLength > 0 {
            self.remoteKnownContextLength = max(512, remoteKnownContextLength)
        } else {
            self.remoteKnownContextLength = nil
        }
        let trimmedRemoteKnownContextSource = remoteKnownContextSource?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.remoteKnownContextSource = trimmedRemoteKnownContextSource?.isEmpty == false
            ? trimmedRemoteKnownContextSource
            : nil
        let trimmedRemoteGroupDisplayName = remoteGroupDisplayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.remoteGroupDisplayName = trimmedRemoteGroupDisplayName?.isEmpty == false
            ? trimmedRemoteGroupDisplayName
            : nil
        let trimmedRemoteProviderModelID = remoteProviderModelID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.remoteProviderModelID = trimmedRemoteProviderModelID?.isEmpty == false
            ? trimmedRemoteProviderModelID
            : nil
        let trimmedRemoteKeyReference = remoteKeyReference?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.remoteKeyReference = trimmedRemoteKeyReference?.isEmpty == false
            ? trimmedRemoteKeyReference
            : nil
        let trimmedRemoteEndpointHost = remoteEndpointHost?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.remoteEndpointHost = trimmedRemoteEndpointHost?.isEmpty == false
            ? trimmedRemoteEndpointHost
            : nil
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
        case remoteConfiguredContextLength
        case remoteKnownContextLength
        case remoteKnownContextSource
        case remoteGroupDisplayName
        case remoteProviderModelID
        case remoteKeyReference
        case remoteEndpointHost
    }

    enum SnakeCodingKeys: String, CodingKey {
        case contextLength = "context_length"
        case maxContextLength = "max_context_length"
        case paramsB = "params_b"
        case memoryBytes = "memory_bytes"
        case tokensPerSec = "tokens_per_sec"
        case modelPath = "model_path"
        case modelFormat = "model_format"
        case defaultLoadConfig = "default_load_config"
        case defaultLoadProfile = "default_load_profile"
        case taskKinds = "task_kinds"
        case inputModalities = "input_modalities"
        case outputModalities = "output_modalities"
        case offlineReady = "offline_ready"
        case voiceProfile = "voice_profile"
        case resourceProfile = "resource_profile"
        case trustProfile = "trust_profile"
        case processorRequirements = "processor_requirements"
        case remoteConfiguredContextLength = "remote_configured_context_length"
        case remoteKnownContextLength = "remote_known_context_length"
        case remoteKnownContextSource = "remote_known_context_source"
        case remoteGroupDisplayName = "remote_group_display_name"
        case remoteProviderModelID = "remote_provider_model_id"
        case remoteKeyReference = "remote_key_reference"
        case remoteEndpointHost = "remote_endpoint_host"
    }

    enum AliasCodingKeys: String, CodingKey {
        case defaultLoadConfig
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        let a = try decoder.container(keyedBy: AliasCodingKeys.self)

        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? id
        backend = (try? c.decode(String.self, forKey: .backend)) ?? "mlx"
        quant = (try? c.decode(String.self, forKey: .quant)) ?? "bf16"
        let legacyContextLength = (try? c.decode(Int.self, forKey: .contextLength))
            ?? (try? s.decode(Int.self, forKey: .contextLength))
            ?? 8192
        let decodedDefaultLoadProfile = (try? a.decodeIfPresent(HubLocalModelLoadProfile.self, forKey: .defaultLoadConfig))
            ?? (try? c.decodeIfPresent(HubLocalModelLoadProfile.self, forKey: .defaultLoadProfile))
            ?? (try? s.decodeIfPresent(HubLocalModelLoadProfile.self, forKey: .defaultLoadConfig))
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
        remoteConfiguredContextLength = (try? c.decodeIfPresent(Int.self, forKey: .remoteConfiguredContextLength))
            ?? (try? s.decodeIfPresent(Int.self, forKey: .remoteConfiguredContextLength))
        if let remoteConfiguredContextLength, remoteConfiguredContextLength > 0 {
            self.remoteConfiguredContextLength = max(512, remoteConfiguredContextLength)
        } else {
            self.remoteConfiguredContextLength = nil
        }
        remoteKnownContextLength = (try? c.decodeIfPresent(Int.self, forKey: .remoteKnownContextLength))
            ?? (try? s.decodeIfPresent(Int.self, forKey: .remoteKnownContextLength))
        if let remoteKnownContextLength, remoteKnownContextLength > 0 {
            self.remoteKnownContextLength = max(512, remoteKnownContextLength)
        } else {
            self.remoteKnownContextLength = nil
        }
        let decodedRemoteKnownContextSource = (try? c.decodeIfPresent(String.self, forKey: .remoteKnownContextSource))
            ?? (try? s.decodeIfPresent(String.self, forKey: .remoteKnownContextSource))
        let trimmedRemoteKnownContextSource = decodedRemoteKnownContextSource?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        remoteKnownContextSource = trimmedRemoteKnownContextSource?.isEmpty == false
            ? trimmedRemoteKnownContextSource
            : nil
        let decodedRemoteGroupDisplayName = (try? c.decodeIfPresent(String.self, forKey: .remoteGroupDisplayName))
            ?? (try? s.decodeIfPresent(String.self, forKey: .remoteGroupDisplayName))
        let trimmedRemoteGroupDisplayName = decodedRemoteGroupDisplayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        remoteGroupDisplayName = trimmedRemoteGroupDisplayName?.isEmpty == false
            ? trimmedRemoteGroupDisplayName
            : nil
        let decodedRemoteProviderModelID = (try? c.decodeIfPresent(String.self, forKey: .remoteProviderModelID))
            ?? (try? s.decodeIfPresent(String.self, forKey: .remoteProviderModelID))
        let trimmedRemoteProviderModelID = decodedRemoteProviderModelID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        remoteProviderModelID = trimmedRemoteProviderModelID?.isEmpty == false
            ? trimmedRemoteProviderModelID
            : nil
        let decodedRemoteKeyReference = (try? c.decodeIfPresent(String.self, forKey: .remoteKeyReference))
            ?? (try? s.decodeIfPresent(String.self, forKey: .remoteKeyReference))
        let trimmedRemoteKeyReference = decodedRemoteKeyReference?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        remoteKeyReference = trimmedRemoteKeyReference?.isEmpty == false
            ? trimmedRemoteKeyReference
            : nil
        let decodedRemoteEndpointHost = (try? c.decodeIfPresent(String.self, forKey: .remoteEndpointHost))
            ?? (try? s.decodeIfPresent(String.self, forKey: .remoteEndpointHost))
        let trimmedRemoteEndpointHost = decodedRemoteEndpointHost?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        remoteEndpointHost = trimmedRemoteEndpointHost?.isEmpty == false
            ? trimmedRemoteEndpointHost
            : nil
    }
}

extension HubModel {
    private func compactContextLength(_ value: Int) -> String {
        guard value > 0 else { return "默认" }
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        }
        if value >= 1_000 {
            return String(format: "%.0fK", Double(value) / 1_000.0)
        }
        return "\(value)"
    }

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
        if let remoteContextDisplayLine {
            return remoteContextDisplayLine
        }
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

    var remoteContextDisplayLine: String? {
        guard !isLocalModel else { return nil }
        let configured = max(512, remoteConfiguredContextLength ?? contextLength)
        let configuredText = compactContextLength(configured)
        if let known = remoteKnownContextLength, known > 0 {
            let knownText = compactContextLength(known)
            switch remoteKnownContextSource?.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "provider_reported":
                return "远端配置窗口：\(configuredText) · Provider 上限：\(knownText)"
            case "catalog_estimate":
                return "远端配置窗口：\(configuredText) · 目录估计：\(knownText)"
            default:
                return "远端配置窗口：\(configuredText) · 已知上限：\(knownText)"
            }
        }
        return "远端配置窗口：\(configuredText) · 真实上限：未回报"
    }

    var isLocalModel: Bool {
        modelPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var isKnownLocalButCurrentlyUnrunnable: Bool {
        guard isLocalModel else { return false }
        guard state != .loaded else { return false }
        return offlineReady == false
    }

    var localExecutionBlockedReason: String? {
        guard isKnownLocalButCurrentlyUnrunnable else { return nil }
        return "Hub 记录的本地 modelPath 当前已失效"
    }

    private func normalizedRemoteIdentityToken(_ raw: String?) -> String {
        (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
    }

    private var trimmedRemoteGroupDisplayName: String? {
        let trimmed = (remoteGroupDisplayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var trimmedRemoteProviderModelID: String? {
        let trimmed = (remoteProviderModelID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var trimmedRemoteKeyReference: String? {
        let trimmed = (remoteKeyReference ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var trimmedRemoteEndpointHost: String? {
        let trimmed = (remoteEndpointHost ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var remoteDisplayName: String? {
        guard !isLocalModel else { return nil }
        let nestedDisplayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let groupDisplayName = trimmedRemoteGroupDisplayName else {
            return nestedDisplayName.isEmpty ? nil : nestedDisplayName
        }
        let fallbackTitle = nestedDisplayName.isEmpty ? id : nestedDisplayName
        guard !fallbackTitle.isEmpty else { return groupDisplayName }
        if normalizedRemoteIdentityToken(groupDisplayName) == normalizedRemoteIdentityToken(fallbackTitle) {
            return fallbackTitle
        }
        return "\(groupDisplayName) · \(fallbackTitle)"
    }

    var remoteIdentityComponents: [HubModelRemoteIdentityComponent] {
        guard !isLocalModel else { return [] }
        var components: [HubModelRemoteIdentityComponent] = []
        var seen = Set<String>()

        func append(_ kind: HubModelRemoteIdentityComponentKind, value rawValue: String?) {
            let trimmed = (rawValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let token = "\(kind.rawValue)::\(normalizedRemoteIdentityToken(trimmed))"
            guard seen.insert(token).inserted else { return }
            components.append(HubModelRemoteIdentityComponent(kind: kind, value: trimmed))
        }

        append(.keyReference, value: trimmedRemoteKeyReference)
        append(.endpointHost, value: trimmedRemoteEndpointHost)

        if let providerModelID = trimmedRemoteProviderModelID {
            let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedRemoteIdentityToken(providerModelID) != normalizedRemoteIdentityToken(displayName) {
                append(.providerModelID, value: providerModelID)
            }
        }

        return components
    }

    func remoteSourceIdentityLine(language: XTInterfaceLanguage = .defaultPreference) -> String? {
        guard !isLocalModel else { return nil }
        let parts = remoteIdentityComponents.compactMap { component -> String? in
            switch component.kind {
            case .keyReference:
                return "Key \(component.value)"
            case .endpointHost:
                return component.value
            case .providerModelID:
                let providerPrefix = XTL10n.text(language, zhHans: "上游", en: "Upstream")
                return "\(providerPrefix) \(component.value)"
            }
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "  ·  ")
    }

    var remoteSearchKeywords: [String] {
        var values: [String?] = [
            remoteDisplayName,
            trimmedRemoteGroupDisplayName,
            trimmedRemoteProviderModelID,
            trimmedRemoteKeyReference,
            trimmedRemoteEndpointHost,
            remoteSourceIdentityLine()
        ]
        values.append(contentsOf: remoteIdentityComponents.map(\.value))
        return values.compactMap { value in
            let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    var isEmbeddingModel: Bool {
        normalizedTaskKindSet.contains("embedding")
    }

    var supportsInteractiveTextGeneration: Bool {
        normalizedTaskKindSet.contains("text_generate")
    }

    var isEmbeddingOnlyModel: Bool {
        guard isEmbeddingModel else { return false }
        return !supportsInteractiveTextGeneration
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
        return !supportsInteractiveTextGeneration
    }

    var isNonInteractiveOnlyModel: Bool {
        !supportsInteractiveTextGeneration
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
        if isNonInteractiveOnlyModel {
            let taskLabels = taskKinds.compactMap(Self.taskKindLabel(_:))
            let joinedTasks = taskLabels.isEmpty ? "任务专用" : taskLabels.joined(separator: " / ")
            return "\(joinedTasks)模型当前只会走任务专用链路；XT 还没有把它接成可手动选择的聊天路由。"
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

    var memoryPromptProjectionFromMetadata: HubMemoryPromptProjectionSnapshot? {
        HubMemoryPromptProjectionSnapshot(metadataValue: raw?["memory_prompt_projection"])
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
    var memoryPromptProjection: HubMemoryPromptProjectionSnapshot?
}

struct HubMemoryPromptProjectionSnapshot: Codable, Equatable, Sendable {
    static let defaultProjectionSource = "hub_generate_done_metadata"

    var projectionSource: String
    var canonicalItemCount: Int
    var workingSetTurnCount: Int
    var runtimeTruthItemCount: Int
    var runtimeTruthSourceKinds: [String]

    init(
        projectionSource: String = defaultProjectionSource,
        canonicalItemCount: Int,
        workingSetTurnCount: Int,
        runtimeTruthItemCount: Int,
        runtimeTruthSourceKinds: [String]
    ) {
        let normalizedProjectionSource = projectionSource.trimmingCharacters(in: .whitespacesAndNewlines)
        self.projectionSource = normalizedProjectionSource.isEmpty
            ? Self.defaultProjectionSource
            : normalizedProjectionSource
        self.canonicalItemCount = max(0, canonicalItemCount)
        self.workingSetTurnCount = max(0, workingSetTurnCount)
        self.runtimeTruthItemCount = max(0, runtimeTruthItemCount)
        self.runtimeTruthSourceKinds = Self.orderedUniqueKinds(runtimeTruthSourceKinds)
    }

    init?(metadataValue: JSONValue?) {
        guard let object = metadataValue?.objectValue else {
            return nil
        }
        let projection = HubMemoryPromptProjectionSnapshot(
            projectionSource: object["projection_source"]?.stringValue ?? Self.defaultProjectionSource,
            canonicalItemCount: object["canonical_item_count"]?.intValue ?? 0,
            workingSetTurnCount: object["working_set_turn_count"]?.intValue ?? 0,
            runtimeTruthItemCount: object["runtime_truth_item_count"]?.intValue ?? 0,
            runtimeTruthSourceKinds: object["runtime_truth_source_kinds"]?.stringArrayValue ?? []
        )
        guard projection.canonicalItemCount > 0
                || projection.workingSetTurnCount > 0
                || projection.runtimeTruthItemCount > 0
                || !projection.runtimeTruthSourceKinds.isEmpty else {
            return nil
        }
        self = projection
    }

    var jsonValue: JSONValue {
        .object(
            [
                "projection_source": .string(projectionSource),
                "canonical_item_count": .number(Double(canonicalItemCount)),
                "working_set_turn_count": .number(Double(workingSetTurnCount)),
                "runtime_truth_item_count": .number(Double(runtimeTruthItemCount)),
                "runtime_truth_source_kinds": .array(runtimeTruthSourceKinds.map(JSONValue.string))
            ]
        )
    }

    func doctorDetailLines(prefix: String = "hub_memory_prompt_projection") -> [String] {
        var lines = [
            "\(prefix)_projection_source=\(projectionSource)",
            "\(prefix)_canonical_item_count=\(canonicalItemCount)",
            "\(prefix)_working_set_turn_count=\(workingSetTurnCount)",
            "\(prefix)_runtime_truth_item_count=\(runtimeTruthItemCount)"
        ]
        if !runtimeTruthSourceKinds.isEmpty {
            lines.append("\(prefix)_runtime_truth_source_kinds=\(runtimeTruthSourceKinds.joined(separator: ","))")
        }
        return lines
    }

    static func fromDoctorDetailLines(
        _ detailLines: [String],
        prefix: String = "hub_memory_prompt_projection"
    ) -> HubMemoryPromptProjectionSnapshot? {
        func lineValue(_ key: String) -> String? {
            guard let line = detailLines.first(where: { $0.hasPrefix("\(key)=") }) else {
                return nil
            }
            return String(line.dropFirst(key.count + 1))
        }

        let projection = HubMemoryPromptProjectionSnapshot(
            projectionSource: lineValue("\(prefix)_projection_source") ?? Self.defaultProjectionSource,
            canonicalItemCount: Int(lineValue("\(prefix)_canonical_item_count") ?? "") ?? 0,
            workingSetTurnCount: Int(lineValue("\(prefix)_working_set_turn_count") ?? "") ?? 0,
            runtimeTruthItemCount: Int(lineValue("\(prefix)_runtime_truth_item_count") ?? "") ?? 0,
            runtimeTruthSourceKinds: (lineValue("\(prefix)_runtime_truth_source_kinds") ?? "")
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        )
        guard projection.canonicalItemCount > 0
                || projection.workingSetTurnCount > 0
                || projection.runtimeTruthItemCount > 0
                || !projection.runtimeTruthSourceKinds.isEmpty else {
            return nil
        }
        return projection
    }

    private static func orderedUniqueKinds(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            ordered.append(trimmed)
        }
        return ordered
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        self.init(
            projectionSource: try container.decodeIfPresent(String.self, forKey: .projectionSource)
                ?? legacyContainer.decodeIfPresent(String.self, forKey: .projectionSource)
                ?? Self.defaultProjectionSource,
            canonicalItemCount: try container.decodeIfPresent(Int.self, forKey: .canonicalItemCount)
                ?? legacyContainer.decodeIfPresent(Int.self, forKey: .canonicalItemCount)
                ?? 0,
            workingSetTurnCount: try container.decodeIfPresent(Int.self, forKey: .workingSetTurnCount)
                ?? legacyContainer.decodeIfPresent(Int.self, forKey: .workingSetTurnCount)
                ?? 0,
            runtimeTruthItemCount: try container.decodeIfPresent(Int.self, forKey: .runtimeTruthItemCount)
                ?? legacyContainer.decodeIfPresent(Int.self, forKey: .runtimeTruthItemCount)
                ?? 0,
            runtimeTruthSourceKinds: try container.decodeIfPresent([String].self, forKey: .runtimeTruthSourceKinds)
                ?? legacyContainer.decodeIfPresent([String].self, forKey: .runtimeTruthSourceKinds)
                ?? []
        )
    }

    enum CodingKeys: String, CodingKey {
        case projectionSource = "projection_source"
        case canonicalItemCount = "canonical_item_count"
        case workingSetTurnCount = "working_set_turn_count"
        case runtimeTruthItemCount = "runtime_truth_item_count"
        case runtimeTruthSourceKinds = "runtime_truth_source_kinds"
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case projectionSource
        case canonicalItemCount
        case workingSetTurnCount
        case runtimeTruthItemCount
        case runtimeTruthSourceKinds
    }
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

    var intValue: Int? {
        switch self {
        case .number(let value):
            return Int(value.rounded())
        case .string(let value):
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case .bool(let value):
            return value ? 1 : 0
        default:
            return nil
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else {
            return nil
        }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else {
            return nil
        }
        return value
    }

    var stringArrayValue: [String] {
        guard let arrayValue else { return [] }
        var seen = Set<String>()
        var ordered: [String] = []
        for item in arrayValue {
            guard let value = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  seen.insert(value).inserted else {
                continue
            }
            ordered.append(value)
        }
        return ordered
    }
}
