import Foundation

extension XTVisibleHubModelInventorySupport {
    static func build(rustInventory projection: XTRustModelInventoryProjection) -> XTVisibleHubModelInventory {
        build(snapshot: projection.snapshot)
    }
}

struct XTRustModelInventoryProjection: Equatable {
    var schemaVersion: String
    var snapshot: ModelStateSnapshot
    var remoteModels: [XTRustRemoteModelInventoryRow]
    var localModels: [XTRustLocalModelInventoryRow]
    var localCapabilitySummary: XTRustLocalCapabilitySummary?

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
        "local_models.runtime_preflight.runtime_missing_requirements",
        "local_capability_summary.by_task.*.task_kind",
        "local_capability_summary.by_task.*.ready",
        "local_capability_summary.by_task.*.state",
        "local_capability_summary.by_task.*.repair_action",
        "local_capability_summary.coverage_state",
        "local_capability_summary.all_tasks_ready",
        "local_capability_summary.providers.*.provider_id",
        "local_capability_summary.providers.*.runtime_missing_requirements"
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
            localModels: localRows,
            localCapabilitySummary: XTRustLocalCapabilitySummary(
                jsonObject: XTRustInventoryJSON.object(
                    object["local_capability_summary"] ?? object["localCapabilitySummary"]
                )
            )
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
        case "vision.understand", "vision.describe", "image.describe", "image.understand":
            return "vision_understand"
        case "vision.ocr", "ocr":
            return "ocr"
        case "speech.to.text", "audio.transcribe", "transcribe", "asr":
            return "speech_to_text"
        case "text.to.speech", "audio.tts", "tts":
            return "text_to_speech"
        default:
            return "text_generate"
        }
    }
}

struct XTRustLocalCapabilitySummary: Equatable {
    var schemaVersion: String
    var ready: Bool
    var allTasksReady: Bool
    var coverageState: String
    var readyTaskCount: Int
    var taskCount: Int
    var tasksByKind: [String: XTRustLocalCapabilityTask]
    var providers: [XTRustRuntimeProviderSummary]

    init?(jsonObject: [String: Any]) {
        guard !jsonObject.isEmpty else { return nil }
        schemaVersion = XTRustInventoryJSON.string(jsonObject["schema_version"] ?? jsonObject["schemaVersion"])
        ready = XTRustInventoryJSON.bool(jsonObject["ready"]) ?? false
        allTasksReady = XTRustInventoryJSON.bool(jsonObject["all_tasks_ready"] ?? jsonObject["allTasksReady"]) ?? false
        coverageState = XTRustInventoryJSON.lowercasedString(jsonObject["coverage_state"] ?? jsonObject["coverageState"])
        readyTaskCount = XTRustInventoryJSON.int(jsonObject["ready_task_count"] ?? jsonObject["readyTaskCount"]) ?? 0
        taskCount = XTRustInventoryJSON.int(jsonObject["task_count"] ?? jsonObject["taskCount"]) ?? 0
        let rawTasks = XTRustInventoryJSON.object(jsonObject["by_task"] ?? jsonObject["byTask"])
        var tasks: [String: XTRustLocalCapabilityTask] = [:]
        for (key, rawValue) in rawTasks {
            let task = XTRustLocalCapabilityTask(
                fallbackTaskKind: key,
                jsonObject: XTRustInventoryJSON.object(rawValue)
            )
            guard !task.taskKind.isEmpty else { continue }
            tasks[task.taskKind] = task
        }
        tasksByKind = tasks
        providers = XTRustInventoryJSON.array(jsonObject["providers"]).compactMap { rawValue in
            let object = XTRustInventoryJSON.object(rawValue)
            guard !object.isEmpty else { return nil }
            return XTRustRuntimeProviderSummary(jsonObject: object)
        }
    }

    func task(_ taskKind: String) -> XTRustLocalCapabilityTask? {
        tasksByKind[taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }
}

struct XTRustLocalCapabilityTask: Equatable {
    var taskKind: String
    var capability: String
    var ready: Bool
    var state: String
    var readyModelCount: Int
    var candidateModelCount: Int
    var primaryBlockingReasonCode: String
    var repairAction: String

    init(fallbackTaskKind: String, jsonObject: [String: Any]) {
        taskKind = XTRustInventoryJSON.lowercasedString(jsonObject["task_kind"] ?? jsonObject["taskKind"])
        if taskKind.isEmpty {
            taskKind = fallbackTaskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        capability = XTRustInventoryJSON.lowercasedString(jsonObject["capability"])
        ready = XTRustInventoryJSON.bool(jsonObject["ready"]) ?? false
        state = XTRustInventoryJSON.lowercasedString(jsonObject["state"])
        readyModelCount = XTRustInventoryJSON.int(jsonObject["ready_model_count"] ?? jsonObject["readyModelCount"]) ?? 0
        candidateModelCount = XTRustInventoryJSON.int(jsonObject["candidate_model_count"] ?? jsonObject["candidateModelCount"]) ?? 0
        primaryBlockingReasonCode = XTRustInventoryJSON.lowercasedString(
            jsonObject["primary_blocking_reason_code"] ?? jsonObject["primaryBlockingReasonCode"]
        )
        repairAction = XTRustInventoryJSON.lowercasedString(jsonObject["repair_action"] ?? jsonObject["repairAction"])
    }
}

struct XTRustRuntimeProviderSummary: Equatable {
    var providerID: String
    var ok: Bool
    var reasonCode: String
    var availableTaskKinds: [String]
    var runtimeMissingRequirements: [String]
    var repairAction: String

    init(jsonObject: [String: Any]) {
        providerID = XTRustInventoryJSON.lowercasedString(jsonObject["provider_id"] ?? jsonObject["providerId"])
        ok = XTRustInventoryJSON.bool(jsonObject["ok"]) ?? false
        reasonCode = XTRustInventoryJSON.lowercasedString(jsonObject["reason_code"] ?? jsonObject["reasonCode"])
        availableTaskKinds = XTRustInventoryJSON.stringList(jsonObject["available_task_kinds"] ?? jsonObject["availableTaskKinds"])
        runtimeMissingRequirements = XTRustInventoryJSON.stringList(
            jsonObject["runtime_missing_requirements"] ?? jsonObject["runtimeMissingRequirements"]
        )
        repairAction = XTRustInventoryJSON.lowercasedString(jsonObject["repair_action"] ?? jsonObject["repairAction"])
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

struct XTRustModelRepairPlanProjection: Equatable {
    var schemaVersion: String
    var state: String
    var safeToAutoApply: Bool
    var requiresUserApproval: Bool
    var requiresNetwork: Bool
    var requiresDownload: Bool
    var secretFieldsIncluded: Bool
    var summary: String
    var resolved: XTRustModelRepairPlanResolved
    var target: XTRustModelRepairPlanTarget
    var requirements: XTRustModelRepairPlanRequirements
    var missingRequirements: [String]
    var steps: [XTRustModelRepairPlanStep]

    static let consumedFieldNames: [String] = [
        "schema_version",
        "resolved.action",
        "resolved.task_kind",
        "resolved.provider_id",
        "state",
        "safe_to_auto_apply",
        "requires_user_approval",
        "requires_network",
        "requires_download",
        "target.kind",
        "target.provider_id",
        "target.task_kind",
        "requirements.python_import_modules",
        "requirements.python_packages",
        "requirements.helper_binary",
        "missing_requirements",
        "steps.*.action_kind",
        "steps.*.requires_user_approval",
        "secret_fields_included"
    ]

    static func decode(from data: Data) throws -> XTRustModelRepairPlanProjection {
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let object = raw as? [String: Any] else {
            throw XTRustModelInventoryProjectionError.invalidTopLevel
        }
        return XTRustModelRepairPlanProjection(jsonObject: object)
    }

    init(jsonObject: [String: Any]) {
        schemaVersion = XTRustInventoryJSON.lowercasedString(jsonObject["schema_version"] ?? jsonObject["schemaVersion"])
        state = XTRustInventoryJSON.lowercasedString(jsonObject["state"])
        safeToAutoApply = XTRustInventoryJSON.bool(jsonObject["safe_to_auto_apply"] ?? jsonObject["safeToAutoApply"]) ?? false
        requiresUserApproval = XTRustInventoryJSON.bool(jsonObject["requires_user_approval"] ?? jsonObject["requiresUserApproval"]) ?? false
        requiresNetwork = XTRustInventoryJSON.bool(jsonObject["requires_network"] ?? jsonObject["requiresNetwork"]) ?? false
        requiresDownload = XTRustInventoryJSON.bool(jsonObject["requires_download"] ?? jsonObject["requiresDownload"]) ?? false
        secretFieldsIncluded = XTRustInventoryJSON.bool(jsonObject["secret_fields_included"] ?? jsonObject["secretFieldsIncluded"]) ?? false
        summary = XTRustInventoryJSON.string(jsonObject["summary"])
        resolved = XTRustModelRepairPlanResolved(
            jsonObject: XTRustInventoryJSON.object(jsonObject["resolved"])
        )
        target = XTRustModelRepairPlanTarget(
            jsonObject: XTRustInventoryJSON.object(jsonObject["target"])
        )
        requirements = XTRustModelRepairPlanRequirements(
            jsonObject: XTRustInventoryJSON.object(jsonObject["requirements"])
        )
        missingRequirements = XTRustInventoryJSON.stringList(jsonObject["missing_requirements"] ?? jsonObject["missingRequirements"])
        steps = XTRustInventoryJSON.array(jsonObject["steps"]).compactMap { raw in
            let object = XTRustInventoryJSON.object(raw)
            guard !object.isEmpty else { return nil }
            return XTRustModelRepairPlanStep(jsonObject: object)
        }
    }
}

struct XTRustModelRepairPlanResolved: Equatable {
    var action: String
    var taskKind: String
    var providerID: String
    var source: String

    init(jsonObject: [String: Any]) {
        action = XTRustInventoryJSON.lowercasedString(jsonObject["action"])
        taskKind = XTRustInventoryJSON.lowercasedString(jsonObject["task_kind"] ?? jsonObject["taskKind"])
        providerID = XTRustInventoryJSON.lowercasedString(jsonObject["provider_id"] ?? jsonObject["providerId"])
        source = XTRustInventoryJSON.lowercasedString(jsonObject["source"])
    }
}

struct XTRustModelRepairPlanTarget: Equatable {
    var kind: String
    var providerID: String
    var taskKind: String

    init(jsonObject: [String: Any]) {
        kind = XTRustInventoryJSON.lowercasedString(jsonObject["kind"])
        providerID = XTRustInventoryJSON.lowercasedString(jsonObject["provider_id"] ?? jsonObject["providerId"])
        taskKind = XTRustInventoryJSON.lowercasedString(jsonObject["task_kind"] ?? jsonObject["taskKind"])
    }
}

struct XTRustModelRepairPlanRequirements: Equatable {
    var engine: String
    var executionMode: String
    var installTarget: String
    var pythonImportModules: [String]
    var pythonPackages: [String]
    var helperBinary: String
    var expectedTaskKinds: [String]
    var supportedDomains: [String]
    var expectedCapability: String

    init(jsonObject: [String: Any]) {
        engine = XTRustInventoryJSON.lowercasedString(jsonObject["engine"])
        executionMode = XTRustInventoryJSON.lowercasedString(jsonObject["execution_mode"] ?? jsonObject["executionMode"])
        installTarget = XTRustInventoryJSON.lowercasedString(jsonObject["install_target"] ?? jsonObject["installTarget"])
        pythonImportModules = XTRustInventoryJSON.stringList(jsonObject["python_import_modules"] ?? jsonObject["pythonImportModules"])
        pythonPackages = XTRustInventoryJSON.stringList(jsonObject["python_packages"] ?? jsonObject["pythonPackages"])
        helperBinary = XTRustInventoryJSON.lowercasedString(jsonObject["helper_binary"] ?? jsonObject["helperBinary"])
        expectedTaskKinds = XTRustInventoryJSON.stringList(jsonObject["expected_task_kinds"] ?? jsonObject["expectedTaskKinds"])
        supportedDomains = XTRustInventoryJSON.stringList(jsonObject["supported_domains"] ?? jsonObject["supportedDomains"])
        expectedCapability = XTRustInventoryJSON.lowercasedString(jsonObject["expected_capability"] ?? jsonObject["expectedCapability"])
    }
}

struct XTRustModelRepairPlanStep: Equatable {
    var stepID: String
    var actionKind: String
    var title: String
    var description: String
    var requiresUserApproval: Bool
    var requiresNetwork: Bool

    init(jsonObject: [String: Any]) {
        stepID = XTRustInventoryJSON.lowercasedString(jsonObject["step_id"] ?? jsonObject["stepID"])
        actionKind = XTRustInventoryJSON.lowercasedString(jsonObject["action_kind"] ?? jsonObject["actionKind"])
        title = XTRustInventoryJSON.string(jsonObject["title"])
        description = XTRustInventoryJSON.string(jsonObject["description"])
        requiresUserApproval = XTRustInventoryJSON.bool(jsonObject["requires_user_approval"] ?? jsonObject["requiresUserApproval"]) ?? false
        requiresNetwork = XTRustInventoryJSON.bool(jsonObject["requires_network"] ?? jsonObject["requiresNetwork"]) ?? false
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
