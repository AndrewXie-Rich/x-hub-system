import Foundation

struct XTVisibleHubModelInventory {
    static let empty = XTVisibleHubModelInventory(
        snapshot: .empty(),
        sortedModels: [],
        modelsByNormalizedID: [:]
    )

    let snapshot: ModelStateSnapshot
    let sortedModels: [HubModel]
    private let modelsByNormalizedID: [String: HubModel]

    func model(for modelId: String?) -> HubModel? {
        let normalized = XTVisibleHubModelInventorySupport.normalizedModelID(modelId)
        guard !normalized.isEmpty else { return nil }
        return modelsByNormalizedID[normalized]
    }

    func presentation(for modelId: String?) -> ModelInfo? {
        let trimmed = XTVisibleHubModelInventorySupport.trimmedModelID(modelId)
        guard !trimmed.isEmpty else { return nil }
        return model(for: trimmed)?.capabilityPresentationModel
            ?? XTModelCatalog.modelInfo(for: trimmed)
    }

    fileprivate init(
        snapshot: ModelStateSnapshot,
        sortedModels: [HubModel],
        modelsByNormalizedID: [String: HubModel]
    ) {
        self.snapshot = snapshot
        self.sortedModels = sortedModels
        self.modelsByNormalizedID = modelsByNormalizedID
    }
}

enum XTVisibleHubModelInventorySupport {
    static func build(snapshot: ModelStateSnapshot) -> XTVisibleHubModelInventory {
        var dedupedModels: [String: HubModel] = [:]
        for model in snapshot.models {
            let normalizedID = normalizedModelID(model.id)
            guard !normalizedID.isEmpty else { continue }
            dedupedModels[normalizedID] = model
        }

        let sortedModels = dedupedModels.values.sorted { a, b in
            let leftStateRank = stateRank(a.state)
            let rightStateRank = stateRank(b.state)
            if leftStateRank != rightStateRank {
                return leftStateRank < rightStateRank
            }

            let leftName = trimmedModelID(a.name).isEmpty ? trimmedModelID(a.id) : trimmedModelID(a.name)
            let rightName = trimmedModelID(b.name).isEmpty ? trimmedModelID(b.id) : trimmedModelID(b.name)
            let leftNormalizedName = leftName.lowercased()
            let rightNormalizedName = rightName.lowercased()
            if leftNormalizedName != rightNormalizedName {
                return leftNormalizedName < rightNormalizedName
            }

            return trimmedModelID(a.id).lowercased() < trimmedModelID(b.id).lowercased()
        }

        var modelsByNormalizedID: [String: HubModel] = [:]
        for model in sortedModels {
            let normalizedID = normalizedModelID(model.id)
            guard !normalizedID.isEmpty else { continue }
            modelsByNormalizedID[normalizedID] = model
        }

        return XTVisibleHubModelInventory(
            snapshot: ModelStateSnapshot(
                models: sortedModels,
                updatedAt: snapshot.updatedAt
            ),
            sortedModels: sortedModels,
            modelsByNormalizedID: modelsByNormalizedID
        )
    }

    static func build(rustInventory projection: XTRustModelInventoryProjection) -> XTVisibleHubModelInventory {
        build(snapshot: projection.snapshot)
    }

    static func trimmedModelID(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedModelID(_ raw: String?) -> String {
        trimmedModelID(raw).lowercased()
    }

    private static func stateRank(_ state: HubModelState) -> Int {
        switch state {
        case .loaded:
            return 0
        case .available:
            return 1
        case .sleeping:
            return 2
        }
    }
}

struct XTRustModelInventoryProjection: Equatable {
    var schemaVersion: String
    var snapshot: ModelStateSnapshot
    var remoteModels: [XTRustRemoteModelInventoryRow]
    var localModels: [XTRustLocalModelInventoryRow]

    static let consumedFieldNames: [String] = [
        "schema_version",
        "updated_at_ms",
        "remote_models.model_id",
        "remote_models.provider",
        "remote_models.provider_host",
        "remote_models.family_key",
        "remote_models.pool_id",
        "remote_models.availability_state",
        "remote_models.available_account_count",
        "remote_models.total_account_count",
        "remote_models.blocking_reason_code",
        "remote_models.next_retry_at_ms",
        "local_models.model_id",
        "local_models.display_name",
        "local_models.family_key",
        "local_models.artifact_path",
        "local_models.format",
        "local_models.artifact_size_bytes",
        "local_models.checksum",
        "local_models.quantization",
        "local_models.runtime_provider",
        "local_models.availability_state",
        "local_models.blocking_reason_code",
        "local_models.capabilities",
        "local_models.memory_risk",
        "local_models.duplicate_artifact_of",
        "local_models.runtime_preflight.runtime_provider",
        "local_models.runtime_preflight.availability_state",
        "local_models.runtime_preflight.blocking_reason_code",
        "local_models.runtime_preflight.supported_format",
        "local_models.runtime_preflight.side_effect_free",
        "local_models.runtime_preflight.runtime_updated_at_ms",
        "local_models.runtime_preflight.capability_tags",
        "local_models.runtime_preflight.runtime_missing_requirements"
    ]

    var firstRemoteQuotaBlocked: XTRustRemoteModelInventoryRow? {
        remoteModels.first(where: \.isQuotaBlocked)
    }

    var firstRemoteScopeBlocked: XTRustRemoteModelInventoryRow? {
        remoteModels.first(where: \.isScopeBlocked)
    }

    var firstLocalRuntimeMissing: XTRustLocalModelInventoryRow? {
        localModels.first(where: \.isRuntimeMissing)
    }

    var firstLocalCapabilityMismatch: XTRustLocalModelInventoryRow? {
        localModels.first(where: \.isCapabilityMismatch)
    }

    var containsPotentialSecretMaterial: Bool {
        let joined = snapshot.models.map { model in
            [
                model.id,
                model.name,
                model.backend,
                model.quant,
                model.modelPath ?? "",
                model.note ?? "",
                model.remoteProviderModelID ?? "",
                model.remoteKeyReference ?? "",
                model.remoteEndpointHost ?? ""
            ].joined(separator: "\n")
        }.joined(separator: "\n").lowercased()
        return joined.contains("sk-") || joined.contains("refresh_token") || joined.contains("api_key")
    }

    static func load(from url: URL) throws -> XTRustModelInventoryProjection {
        try decode(from: Data(contentsOf: url))
    }

    static func decode(from data: Data) throws -> XTRustModelInventoryProjection {
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let object = raw as? [String: Any] else {
            throw XTRustModelInventoryProjectionError.invalidTopLevel
        }

        let remoteRows = XTRustInventoryJSON.array(
            object["remote_models"] ?? object["remoteModels"]
        ).compactMap { raw -> XTRustRemoteModelInventoryRow? in
            let object = XTRustInventoryJSON.object(raw)
            guard !object.isEmpty else { return nil }
            return XTRustRemoteModelInventoryRow(jsonObject: object)
        }
        let localRows = XTRustInventoryJSON.array(
            object["local_models"] ?? object["localModels"]
        ).compactMap { raw -> XTRustLocalModelInventoryRow? in
            let object = XTRustInventoryJSON.object(raw)
            guard !object.isEmpty else { return nil }
            return XTRustLocalModelInventoryRow(jsonObject: object)
        }
        let updatedAtMs = XTRustInventoryJSON.int64(
            object["updated_at_ms"] ?? object["updatedAtMs"]
        ) ?? 0
        let models = remoteRows.map(\.hubModel) + localRows.map(\.hubModel)
        let sortedModels = XTVisibleHubModelInventorySupport.build(
            snapshot: ModelStateSnapshot(
                models: models,
                updatedAt: updatedAtMs > 0 ? Double(updatedAtMs) / 1000.0 : 0
            )
        ).sortedModels
        return XTRustModelInventoryProjection(
            schemaVersion: XTRustInventoryJSON.string(object["schema_version"] ?? object["schemaVersion"]),
            snapshot: ModelStateSnapshot(
                models: sortedModels,
                updatedAt: updatedAtMs > 0 ? Double(updatedAtMs) / 1000.0 : 0
            ),
            remoteModels: remoteRows,
            localModels: localRows
        )
    }
}

enum XTRustModelInventoryProjectionError: Error, Equatable {
    case invalidTopLevel
}

struct XTRustRemoteModelInventoryRow: Equatable {
    var modelID: String
    var provider: String
    var providerHost: String
    var familyKey: String
    var poolID: String
    var availabilityState: String
    var availableAccountCount: Int
    var totalAccountCount: Int
    var blockingReasonCode: String
    var nextRetryAtMs: Int64

    init(jsonObject: [String: Any]) {
        modelID = XTRustInventoryJSON.string(jsonObject["model_id"] ?? jsonObject["modelId"])
        provider = XTRustInventoryJSON.lowercasedString(jsonObject["provider"])
        providerHost = XTRustInventoryJSON.lowercasedString(jsonObject["provider_host"] ?? jsonObject["providerHost"])
        familyKey = XTRustInventoryJSON.lowercasedString(jsonObject["family_key"] ?? jsonObject["familyKey"])
        poolID = XTRustInventoryJSON.string(jsonObject["pool_id"] ?? jsonObject["poolId"])
        availabilityState = XTRustInventoryJSON.lowercasedString(jsonObject["availability_state"] ?? jsonObject["availabilityState"])
        availableAccountCount = XTRustInventoryJSON.int(jsonObject["available_account_count"] ?? jsonObject["availableAccountCount"]) ?? 0
        totalAccountCount = XTRustInventoryJSON.int(jsonObject["total_account_count"] ?? jsonObject["totalAccountCount"]) ?? 0
        blockingReasonCode = XTRustInventoryJSON.lowercasedString(jsonObject["blocking_reason_code"] ?? jsonObject["blockingReasonCode"])
        nextRetryAtMs = XTRustInventoryJSON.int64(jsonObject["next_retry_at_ms"] ?? jsonObject["nextRetryAtMs"]) ?? 0
    }

    var isReady: Bool {
        availabilityState == "ready" && availableAccountCount > 0 && blockingReasonCode.isEmpty
    }

    var isQuotaBlocked: Bool {
        let token = "\(availabilityState) \(blockingReasonCode)"
        return token.contains("quota") || token.contains("cooldown") || token.contains("rate_limit")
    }

    var isScopeBlocked: Bool {
        let token = "\(availabilityState) \(blockingReasonCode)"
        return token.contains("scope") || token.contains("permission")
    }

    var hubModel: HubModel {
        HubModel(
            id: modelID,
            name: modelID,
            backend: provider.isEmpty ? "remote" : provider,
            quant: "remote",
            contextLength: 8192,
            paramsB: 0,
            state: isReady ? .loaded : .available,
            note: note,
            taskKinds: ["text_generate"],
            offlineReady: false,
            remoteGroupDisplayName: provider.isEmpty ? nil : provider,
            remoteProviderModelID: modelID,
            remoteKeyReference: remoteKeyReference,
            remoteEndpointHost: providerHost.isEmpty ? nil : providerHost
        )
    }

    var note: String? {
        guard !isReady else { return nil }
        var parts: [String] = []
        if !blockingReasonCode.isEmpty {
            parts.append("reason=\(blockingReasonCode)")
        }
        if nextRetryAtMs > 0 {
            parts.append("next_retry_at_ms=\(nextRetryAtMs)")
        }
        if totalAccountCount > 0 {
            parts.append("accounts=\(availableAccountCount)/\(totalAccountCount)")
        }
        return parts.isEmpty ? "remote inventory not ready" : parts.joined(separator: " · ")
    }

    private var remoteKeyReference: String? {
        let provider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        let poolID = poolID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !provider.isEmpty, !poolID.isEmpty else { return nil }
        return "\(provider):\(poolID)"
    }
}

struct XTRustLocalModelInventoryRow: Equatable {
    var modelID: String
    var displayName: String
    var familyKey: String
    var artifactPath: String
    var format: String
    var artifactSizeBytes: Int64
    var checksum: String
    var quantization: String
    var runtimeProvider: String
    var availabilityState: String
    var blockingReasonCode: String
    var capabilities: [String]
    var memoryRisk: String
    var duplicateArtifactOf: String
    var runtimePreflight: XTRustLocalRuntimePreflight

    init(jsonObject: [String: Any]) {
        modelID = XTRustInventoryJSON.string(jsonObject["model_id"] ?? jsonObject["modelId"])
        displayName = XTRustInventoryJSON.string(jsonObject["display_name"] ?? jsonObject["displayName"])
        familyKey = XTRustInventoryJSON.lowercasedString(jsonObject["family_key"] ?? jsonObject["familyKey"])
        artifactPath = XTRustInventoryJSON.string(jsonObject["artifact_path"] ?? jsonObject["artifactPath"])
        format = XTRustInventoryJSON.lowercasedString(jsonObject["format"])
        artifactSizeBytes = XTRustInventoryJSON.int64(jsonObject["artifact_size_bytes"] ?? jsonObject["artifactSizeBytes"]) ?? 0
        checksum = XTRustInventoryJSON.string(jsonObject["checksum"])
        quantization = XTRustInventoryJSON.lowercasedString(jsonObject["quantization"])
        runtimeProvider = XTRustInventoryJSON.lowercasedString(jsonObject["runtime_provider"] ?? jsonObject["runtimeProvider"])
        availabilityState = XTRustInventoryJSON.lowercasedString(jsonObject["availability_state"] ?? jsonObject["availabilityState"])
        blockingReasonCode = XTRustInventoryJSON.lowercasedString(jsonObject["blocking_reason_code"] ?? jsonObject["blockingReasonCode"])
        capabilities = XTRustInventoryJSON.stringList(jsonObject["capabilities"])
        memoryRisk = XTRustInventoryJSON.lowercasedString(jsonObject["memory_risk"] ?? jsonObject["memoryRisk"])
        duplicateArtifactOf = XTRustInventoryJSON.string(jsonObject["duplicate_artifact_of"] ?? jsonObject["duplicateArtifactOf"])
        runtimePreflight = XTRustLocalRuntimePreflight(
            jsonObject: XTRustInventoryJSON.object(jsonObject["runtime_preflight"] ?? jsonObject["runtimePreflight"])
        )
    }

    var isReady: Bool {
        availabilityState == "ready" && blockingReasonCode.isEmpty && runtimePreflight.availabilityState == "ready"
    }

    var isRuntimeMissing: Bool {
        let token = "\(availabilityState) \(blockingReasonCode) \(runtimePreflight.availabilityState) \(runtimePreflight.blockingReasonCode)"
        return token.contains("runtime_status_missing")
            || token.contains("runtime_provider_missing")
            || token.contains("unknown_stale")
    }

    var isCapabilityMismatch: Bool {
        let token = "\(blockingReasonCode) \(runtimePreflight.blockingReasonCode)"
        return token.contains("capability_mismatch") || !runtimePreflight.runtimeMissingRequirements.isEmpty
    }

    var hubModel: HubModel {
        HubModel(
            id: modelID,
            name: displayName.isEmpty ? modelID : displayName,
            backend: runtimeProvider.isEmpty ? "local" : runtimeProvider,
            quant: quantization.isEmpty ? "unknown" : quantization,
            contextLength: 8192,
            paramsB: 0,
            state: isReady ? .loaded : .available,
            memoryBytes: artifactSizeBytes > 0 ? artifactSizeBytes : nil,
            modelPath: artifactPath.isEmpty ? nil : artifactPath,
            note: note,
            modelFormat: format.isEmpty ? nil : format,
            taskKinds: taskKinds,
            offlineReady: isReady
        )
    }

    var note: String? {
        guard !isReady else { return nil }
        var parts: [String] = []
        if !blockingReasonCode.isEmpty {
            parts.append("reason=\(blockingReasonCode)")
        }
        if !runtimePreflight.blockingReasonCode.isEmpty {
            parts.append("runtime=\(runtimePreflight.blockingReasonCode)")
        }
        if !runtimePreflight.runtimeMissingRequirements.isEmpty {
            parts.append("missing=\(runtimePreflight.runtimeMissingRequirements.joined(separator: ","))")
        }
        if !memoryRisk.isEmpty, memoryRisk != "low", memoryRisk != "unknown" {
            parts.append("memory=\(memoryRisk)")
        }
        return parts.isEmpty ? "local inventory not ready" : parts.joined(separator: " · ")
    }

    private var taskKinds: [String] {
        let values = capabilities.map(Self.taskKind(forCapability:))
        let unique = XTRustInventoryJSON.orderedUnique(values)
        return unique.isEmpty ? ["text_generate"] : unique
    }

    private static func taskKind(forCapability capability: String) -> String {
        switch capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "_", with: ".") {
        case "embedding.generate", "embedding", "embeddings":
            return "embedding"
        case "vision.describe", "image.describe":
            return "vision_understand"
        case "vision.ocr", "ocr":
            return "ocr"
        case "audio.transcribe", "transcribe":
            return "speech_to_text"
        case "audio.tts", "tts":
            return "text_to_speech"
        default:
            return "text_generate"
        }
    }
}

struct XTRustLocalRuntimePreflight: Equatable {
    var runtimeProvider: String
    var availabilityState: String
    var blockingReasonCode: String
    var runtimeSource: String
    var runtimeSourcePath: String
    var supportedFormat: Bool
    var sideEffectFree: Bool
    var runtimeUpdatedAtMs: Int64
    var capabilityTags: [String]
    var runtimeMissingRequirements: [String]

    init(jsonObject: [String: Any]) {
        runtimeProvider = XTRustInventoryJSON.lowercasedString(jsonObject["runtime_provider"] ?? jsonObject["runtimeProvider"] ?? jsonObject["provider"])
        availabilityState = XTRustInventoryJSON.lowercasedString(jsonObject["availability_state"] ?? jsonObject["availabilityState"])
        blockingReasonCode = XTRustInventoryJSON.lowercasedString(jsonObject["blocking_reason_code"] ?? jsonObject["blockingReasonCode"])
        runtimeSource = XTRustInventoryJSON.lowercasedString(jsonObject["runtime_source"] ?? jsonObject["runtimeSource"])
        runtimeSourcePath = XTRustInventoryJSON.string(jsonObject["runtime_source_path"] ?? jsonObject["runtimeSourcePath"])
        supportedFormat = XTRustInventoryJSON.bool(jsonObject["supported_format"] ?? jsonObject["supportedFormat"]) ?? false
        sideEffectFree = XTRustInventoryJSON.bool(jsonObject["side_effect_free"] ?? jsonObject["sideEffectFree"]) ?? false
        runtimeUpdatedAtMs = XTRustInventoryJSON.int64(jsonObject["runtime_updated_at_ms"] ?? jsonObject["runtimeUpdatedAtMs"] ?? jsonObject["updated_at_ms"] ?? jsonObject["updatedAtMs"]) ?? 0
        capabilityTags = XTRustInventoryJSON.stringList(jsonObject["capability_tags"] ?? jsonObject["capabilityTags"])
        runtimeMissingRequirements = XTRustInventoryJSON.stringList(jsonObject["runtime_missing_requirements"] ?? jsonObject["runtimeMissingRequirements"])
    }
}

private enum XTRustInventoryJSON {
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
        guard !token.isEmpty else { return nil }
        return Int(token)
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
        guard !token.isEmpty else { return nil }
        return Int64(token)
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
        if let array = value as? [Any] {
            return orderedUnique(
                array.map { string($0).lowercased() }
            )
        }
        return orderedUnique(
            string(value)
                .split { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" }
                .map { String($0).lowercased() }
        )
    }

    static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            let token = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !token.isEmpty, seen.insert(token).inserted else { continue }
            out.append(token)
        }
        return out
    }
}
