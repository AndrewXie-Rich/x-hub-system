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
    public var runtimeSource: String
    public var runtimeSourcePath: String
    public var runtimeResolutionState: String
    public var runtimeReasonCode: String
    public var fallbackUsed: Bool
    public var availableTaskKinds: [String]
    public var loadedModels: [String]
    public var deviceBackend: String
    public var importError: String
    public var loadedModelCount: Int
    public var managedServiceState: AIRuntimeManagedServiceState?
}

public struct AIRuntimeManagedServiceState: Codable, Sendable, Equatable {
    public var baseURL: String
    public var bindHost: String
    public var bindPort: Int
    public var pid: Int
    public var processState: String
    public var startedAtMs: Int64
    public var lastProbeAtMs: Int64
    public var lastProbeHTTPStatus: Int
    public var lastProbeError: String
    public var lastReadyAtMs: Int64
    public var lastLaunchAttemptAtMs: Int64
    public var startAttemptCount: Int
    public var lastStartError: String
    public var updatedAtMs: Int64

    public init(
        baseURL: String = "",
        bindHost: String = "",
        bindPort: Int = 0,
        pid: Int = 0,
        processState: String = "",
        startedAtMs: Int64 = 0,
        lastProbeAtMs: Int64 = 0,
        lastProbeHTTPStatus: Int = 0,
        lastProbeError: String = "",
        lastReadyAtMs: Int64 = 0,
        lastLaunchAttemptAtMs: Int64 = 0,
        startAttemptCount: Int = 0,
        lastStartError: String = "",
        updatedAtMs: Int64 = 0
    ) {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bindHost = bindHost.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bindPort = max(0, bindPort)
        self.pid = max(0, pid)
        self.processState = processState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.startedAtMs = max(0, startedAtMs)
        self.lastProbeAtMs = max(0, lastProbeAtMs)
        self.lastProbeHTTPStatus = max(0, lastProbeHTTPStatus)
        self.lastProbeError = lastProbeError.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastReadyAtMs = max(0, lastReadyAtMs)
        self.lastLaunchAttemptAtMs = max(0, lastLaunchAttemptAtMs)
        self.startAttemptCount = max(0, startAttemptCount)
        self.lastStartError = lastStartError.trimmingCharacters(in: .whitespacesAndNewlines)
        self.updatedAtMs = max(0, updatedAtMs)
    }

    enum CodingKeys: String, CodingKey {
        case baseURL = "baseUrl"
        case bindHost
        case bindPort
        case pid
        case processState
        case startedAtMs
        case lastProbeAtMs
        case lastProbeHTTPStatus = "lastProbeHttpStatus"
        case lastProbeError
        case lastReadyAtMs
        case lastLaunchAttemptAtMs
        case startAttemptCount
        case lastStartError
        case updatedAtMs
    }

    enum SnakeCodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case bindHost = "bind_host"
        case bindPort = "bind_port"
        case pid
        case processState = "process_state"
        case startedAtMs = "started_at_ms"
        case lastProbeAtMs = "last_probe_at_ms"
        case lastProbeHTTPStatus = "last_probe_http_status"
        case lastProbeError = "last_probe_error"
        case lastReadyAtMs = "last_ready_at_ms"
        case lastLaunchAttemptAtMs = "last_launch_attempt_at_ms"
        case startAttemptCount = "start_attempt_count"
        case lastStartError = "last_start_error"
        case updatedAtMs = "updated_at_ms"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        self.init(
            baseURL: (try? c.decodeIfPresent(String.self, forKey: .baseURL))
                ?? (try? s.decodeIfPresent(String.self, forKey: .baseURL))
                ?? "",
            bindHost: (try? c.decodeIfPresent(String.self, forKey: .bindHost))
                ?? (try? s.decodeIfPresent(String.self, forKey: .bindHost))
                ?? "",
            bindPort: (try? c.decodeIfPresent(Int.self, forKey: .bindPort))
                ?? (try? s.decodeIfPresent(Int.self, forKey: .bindPort))
                ?? 0,
            pid: (try? c.decodeIfPresent(Int.self, forKey: .pid))
                ?? (try? s.decodeIfPresent(Int.self, forKey: .pid))
                ?? 0,
            processState: (try? c.decodeIfPresent(String.self, forKey: .processState))
                ?? (try? s.decodeIfPresent(String.self, forKey: .processState))
                ?? "",
            startedAtMs: (try? c.decodeIfPresent(Int64.self, forKey: .startedAtMs))
                ?? (try? s.decodeIfPresent(Int64.self, forKey: .startedAtMs))
                ?? 0,
            lastProbeAtMs: (try? c.decodeIfPresent(Int64.self, forKey: .lastProbeAtMs))
                ?? (try? s.decodeIfPresent(Int64.self, forKey: .lastProbeAtMs))
                ?? 0,
            lastProbeHTTPStatus: (try? c.decodeIfPresent(Int.self, forKey: .lastProbeHTTPStatus))
                ?? (try? s.decodeIfPresent(Int.self, forKey: .lastProbeHTTPStatus))
                ?? 0,
            lastProbeError: (try? c.decodeIfPresent(String.self, forKey: .lastProbeError))
                ?? (try? s.decodeIfPresent(String.self, forKey: .lastProbeError))
                ?? "",
            lastReadyAtMs: (try? c.decodeIfPresent(Int64.self, forKey: .lastReadyAtMs))
                ?? (try? s.decodeIfPresent(Int64.self, forKey: .lastReadyAtMs))
                ?? 0,
            lastLaunchAttemptAtMs: (try? c.decodeIfPresent(Int64.self, forKey: .lastLaunchAttemptAtMs))
                ?? (try? s.decodeIfPresent(Int64.self, forKey: .lastLaunchAttemptAtMs))
                ?? 0,
            startAttemptCount: (try? c.decodeIfPresent(Int.self, forKey: .startAttemptCount))
                ?? (try? s.decodeIfPresent(Int.self, forKey: .startAttemptCount))
                ?? 0,
            lastStartError: (try? c.decodeIfPresent(String.self, forKey: .lastStartError))
                ?? (try? s.decodeIfPresent(String.self, forKey: .lastStartError))
                ?? "",
            updatedAtMs: (try? c.decodeIfPresent(Int64.self, forKey: .updatedAtMs))
                ?? (try? s.decodeIfPresent(Int64.self, forKey: .updatedAtMs))
                ?? 0
        )
    }
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

public enum AIRuntimeProviderHubControlMode: String, Codable, Sendable {
    case mlxLegacy = "mlx_legacy"
    case warmable = "warmable"
    case ephemeralOnDemand = "ephemeral_on_demand"
}

public enum AIRuntimeProviderLifecycleAction: String, Codable, Sendable {
    case warmupLocalModel = "warmup_local_model"
    case unloadLocalModel = "unload_local_model"
    case evictLocalInstance = "evict_local_instance"
}

public struct AIRuntimeLoadedInstance: Codable, Sendable, Equatable {
    public var instanceKey: String
    public var modelId: String
    public var taskKinds: [String]
    public var loadProfileHash: String
    public var effectiveContextLength: Int
    public var maxContextLength: Int
    public var effectiveLoadProfile: LocalModelLoadProfile?
    public var ttl: Int?
    public var progress: Double?
    public var loadedAt: Double
    public var lastUsedAt: Double
    public var residency: String
    public var residencyScope: String
    public var deviceBackend: String

    public var loadConfigHash: String { loadProfileHash }
    public var currentContextLength: Int { effectiveContextLength }
    public var loadConfig: LocalModelLoadProfile? { effectiveLoadProfile }

    public init(
        instanceKey: String,
        modelId: String,
        taskKinds: [String] = [],
        loadProfileHash: String = "",
        effectiveContextLength: Int = 0,
        maxContextLength: Int = 0,
        effectiveLoadProfile: LocalModelLoadProfile? = nil,
        ttl: Int? = nil,
        progress: Double? = nil,
        loadedAt: Double = 0,
        lastUsedAt: Double = 0,
        residency: String = "",
        residencyScope: String = "",
        deviceBackend: String = ""
    ) {
        self.instanceKey = instanceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.taskKinds = LocalModelCapabilityDefaults.normalizedStringList(taskKinds, fallback: [])
        self.loadProfileHash = loadProfileHash.trimmingCharacters(in: .whitespacesAndNewlines)
        self.effectiveContextLength = max(0, effectiveContextLength)
        self.maxContextLength = max(0, maxContextLength)
        self.effectiveLoadProfile = effectiveLoadProfile
        self.ttl = Self.optionalPositiveInt(ttl) ?? effectiveLoadProfile?.ttl
        self.progress = Self.normalizedProgress(progress)
        self.loadedAt = max(0, loadedAt)
        self.lastUsedAt = max(0, lastUsedAt)
        self.residency = residency.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.residencyScope = residencyScope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.deviceBackend = deviceBackend.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CodingKeys: String, CodingKey {
        case instanceKey
        case modelId
        case taskKinds
        case loadProfileHash
        case loadConfigHash
        case effectiveContextLength
        case currentContextLength
        case maxContextLength
        case effectiveLoadProfile
        case loadConfig
        case ttl
        case progress
        case loadedAt
        case lastUsedAt
        case residency
        case residencyScope
        case deviceBackend
    }

    enum SnakeCodingKeys: String, CodingKey {
        case instanceKey = "instance_key"
        case modelId = "model_id"
        case taskKinds = "task_kinds"
        case loadProfileHash = "load_profile_hash"
        case loadConfigHash = "load_config_hash"
        case effectiveContextLength = "effective_context_length"
        case currentContextLength = "current_context_length"
        case maxContextLength = "max_context_length"
        case effectiveLoadProfile = "effective_load_profile"
        case loadConfig = "load_config"
        case ttl
        case progress
        case loadedAt = "loaded_at"
        case lastUsedAt = "last_used_at"
        case residency
        case residencyScope = "residency_scope"
        case deviceBackend = "device_backend"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        let decodedLoadConfig = (try? c.decodeIfPresent(LocalModelLoadProfile.self, forKey: .loadConfig))
            ?? (try? s.decodeIfPresent(LocalModelLoadProfile.self, forKey: .loadConfig))
            ?? (try? c.decodeIfPresent(LocalModelLoadProfile.self, forKey: .effectiveLoadProfile))
            ?? (try? s.decodeIfPresent(LocalModelLoadProfile.self, forKey: .effectiveLoadProfile))
        self.init(
            instanceKey: (try? c.decode(String.self, forKey: .instanceKey))
                ?? (try? s.decode(String.self, forKey: .instanceKey))
                ?? "",
            modelId: (try? c.decode(String.self, forKey: .modelId))
                ?? (try? s.decode(String.self, forKey: .modelId))
                ?? "",
            taskKinds: (try? c.decode([String].self, forKey: .taskKinds))
                ?? (try? s.decode([String].self, forKey: .taskKinds))
                ?? [],
            loadProfileHash: (try? c.decode(String.self, forKey: .loadConfigHash))
                ?? (try? s.decode(String.self, forKey: .loadConfigHash))
                ?? (try? c.decode(String.self, forKey: .loadProfileHash))
                ?? (try? s.decode(String.self, forKey: .loadProfileHash))
                ?? "",
            effectiveContextLength: (try? c.decode(Int.self, forKey: .currentContextLength))
                ?? (try? s.decode(Int.self, forKey: .currentContextLength))
                ?? (try? c.decode(Int.self, forKey: .effectiveContextLength))
                ?? (try? s.decode(Int.self, forKey: .effectiveContextLength))
                ?? 0,
            maxContextLength: (try? c.decode(Int.self, forKey: .maxContextLength))
                ?? (try? s.decode(Int.self, forKey: .maxContextLength))
                ?? 0,
            effectiveLoadProfile: decodedLoadConfig,
            ttl: (try? c.decodeIfPresent(Int.self, forKey: .ttl))
                ?? (try? s.decodeIfPresent(Int.self, forKey: .ttl)),
            progress: (try? c.decodeIfPresent(Double.self, forKey: .progress))
                ?? (try? s.decodeIfPresent(Double.self, forKey: .progress)),
            loadedAt: (try? c.decode(Double.self, forKey: .loadedAt))
                ?? (try? s.decode(Double.self, forKey: .loadedAt))
                ?? 0,
            lastUsedAt: (try? c.decode(Double.self, forKey: .lastUsedAt))
                ?? (try? s.decode(Double.self, forKey: .lastUsedAt))
                ?? 0,
            residency: (try? c.decode(String.self, forKey: .residency))
                ?? (try? s.decode(String.self, forKey: .residency))
                ?? "",
            residencyScope: (try? c.decode(String.self, forKey: .residencyScope))
                ?? (try? s.decode(String.self, forKey: .residencyScope))
                ?? "",
            deviceBackend: (try? c.decode(String.self, forKey: .deviceBackend))
                ?? (try? s.decode(String.self, forKey: .deviceBackend))
                ?? ""
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(instanceKey, forKey: .instanceKey)
        try c.encode(modelId, forKey: .modelId)
        try c.encode(taskKinds, forKey: .taskKinds)
        try c.encode(loadProfileHash, forKey: .loadProfileHash)
        try c.encode(loadConfigHash, forKey: .loadConfigHash)
        try c.encode(effectiveContextLength, forKey: .effectiveContextLength)
        try c.encode(currentContextLength, forKey: .currentContextLength)
        try c.encode(maxContextLength, forKey: .maxContextLength)
        try c.encodeIfPresent(effectiveLoadProfile, forKey: .effectiveLoadProfile)
        try c.encodeIfPresent(loadConfig, forKey: .loadConfig)
        try c.encodeIfPresent(ttl, forKey: .ttl)
        try c.encodeIfPresent(progress, forKey: .progress)
        try c.encode(loadedAt, forKey: .loadedAt)
        try c.encode(lastUsedAt, forKey: .lastUsedAt)
        try c.encode(residency, forKey: .residency)
        try c.encode(residencyScope, forKey: .residencyScope)
        try c.encode(deviceBackend, forKey: .deviceBackend)
    }

    private static func optionalPositiveInt(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func normalizedProgress(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(1.0, max(0.0, value))
    }
}

public extension AIRuntimeStatus {
    static let recommendedHeartbeatTTL: Double = 12.0
}

public struct AIRuntimeMonitorProvider: Codable, Sendable, Equatable {
    public var provider: String
    public var ok: Bool
    public var reasonCode: String
    public var importError: String
    public var runtimeSource: String
    public var runtimeResolutionState: String
    public var runtimeReasonCode: String
    public var fallbackUsed: Bool
    public var availableTaskKinds: [String]
    public var realTaskKinds: [String]
    public var fallbackTaskKinds: [String]
    public var unavailableTaskKinds: [String]
    public var deviceBackend: String
    public var lifecycleMode: String
    public var residencyScope: String
    public var loadedInstanceCount: Int
    public var loadedModelCount: Int
    public var activeTaskCount: Int
    public var queuedTaskCount: Int
    public var concurrencyLimit: Int
    public var queueMode: String
    public var queueingSupported: Bool
    public var oldestWaiterStartedAt: Double
    public var oldestWaiterAgeMs: Int
    public var contentionCount: Int
    public var lastContentionAt: Double
    public var activeMemoryBytes: Int64
    public var peakMemoryBytes: Int64
    public var memoryState: String
    public var idleEvictionPolicy: String
    public var lastIdleEvictionReason: String
    public var updatedAt: Double

    public init(
        provider: String,
        ok: Bool = false,
        reasonCode: String = "",
        importError: String = "",
        runtimeSource: String = "",
        runtimeResolutionState: String = "",
        runtimeReasonCode: String = "",
        fallbackUsed: Bool = false,
        availableTaskKinds: [String] = [],
        realTaskKinds: [String] = [],
        fallbackTaskKinds: [String] = [],
        unavailableTaskKinds: [String] = [],
        deviceBackend: String = "",
        lifecycleMode: String = "",
        residencyScope: String = "",
        loadedInstanceCount: Int = 0,
        loadedModelCount: Int = 0,
        activeTaskCount: Int = 0,
        queuedTaskCount: Int = 0,
        concurrencyLimit: Int = 1,
        queueMode: String = "",
        queueingSupported: Bool = false,
        oldestWaiterStartedAt: Double = 0,
        oldestWaiterAgeMs: Int = 0,
        contentionCount: Int = 0,
        lastContentionAt: Double = 0,
        activeMemoryBytes: Int64 = 0,
        peakMemoryBytes: Int64 = 0,
        memoryState: String = "",
        idleEvictionPolicy: String = "",
        lastIdleEvictionReason: String = "",
        updatedAt: Double = 0
    ) {
        self.provider = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.ok = ok
        self.reasonCode = reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.importError = importError.trimmingCharacters(in: .whitespacesAndNewlines)
        self.runtimeSource = runtimeSource.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.runtimeResolutionState = runtimeResolutionState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.runtimeReasonCode = runtimeReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fallbackUsed = fallbackUsed
        self.availableTaskKinds = LocalModelCapabilityDefaults.normalizedStringList(availableTaskKinds, fallback: [])
        self.realTaskKinds = LocalModelCapabilityDefaults.normalizedStringList(realTaskKinds, fallback: [])
        self.fallbackTaskKinds = LocalModelCapabilityDefaults.normalizedStringList(fallbackTaskKinds, fallback: [])
        self.unavailableTaskKinds = LocalModelCapabilityDefaults.normalizedStringList(unavailableTaskKinds, fallback: [])
        self.deviceBackend = deviceBackend.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lifecycleMode = lifecycleMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.residencyScope = residencyScope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.loadedInstanceCount = max(0, loadedInstanceCount)
        self.loadedModelCount = max(0, loadedModelCount)
        self.activeTaskCount = max(0, activeTaskCount)
        self.queuedTaskCount = max(0, queuedTaskCount)
        self.concurrencyLimit = max(1, concurrencyLimit)
        self.queueMode = queueMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.queueingSupported = queueingSupported
        self.oldestWaiterStartedAt = max(0, oldestWaiterStartedAt)
        self.oldestWaiterAgeMs = max(0, oldestWaiterAgeMs)
        self.contentionCount = max(0, contentionCount)
        self.lastContentionAt = max(0, lastContentionAt)
        self.activeMemoryBytes = max(0, activeMemoryBytes)
        self.peakMemoryBytes = max(0, peakMemoryBytes)
        self.memoryState = memoryState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.idleEvictionPolicy = idleEvictionPolicy.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.lastIdleEvictionReason = lastIdleEvictionReason.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.updatedAt = max(0, updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case ok
        case reasonCode
        case importError
        case runtimeSource
        case runtimeResolutionState
        case runtimeReasonCode
        case fallbackUsed
        case availableTaskKinds
        case realTaskKinds
        case fallbackTaskKinds
        case unavailableTaskKinds
        case deviceBackend
        case lifecycleMode
        case residencyScope
        case loadedInstanceCount
        case loadedModelCount
        case activeTaskCount
        case queuedTaskCount
        case concurrencyLimit
        case queueMode
        case queueingSupported
        case oldestWaiterStartedAt
        case oldestWaiterAgeMs
        case contentionCount
        case lastContentionAt
        case activeMemoryBytes
        case peakMemoryBytes
        case memoryState
        case idleEvictionPolicy
        case lastIdleEvictionReason
        case updatedAt
    }

    enum SnakeCodingKeys: String, CodingKey {
        case provider
        case ok
        case reasonCode = "reason_code"
        case importError = "import_error"
        case runtimeSource = "runtime_source"
        case runtimeResolutionState = "runtime_resolution_state"
        case runtimeReasonCode = "runtime_reason_code"
        case fallbackUsed = "fallback_used"
        case availableTaskKinds = "available_task_kinds"
        case realTaskKinds = "real_task_kinds"
        case fallbackTaskKinds = "fallback_task_kinds"
        case unavailableTaskKinds = "unavailable_task_kinds"
        case deviceBackend = "device_backend"
        case lifecycleMode = "lifecycle_mode"
        case residencyScope = "residency_scope"
        case loadedInstanceCount = "loaded_instance_count"
        case loadedModelCount = "loaded_model_count"
        case activeTaskCount = "active_task_count"
        case queuedTaskCount = "queued_task_count"
        case concurrencyLimit = "concurrency_limit"
        case queueMode = "queue_mode"
        case queueingSupported = "queueing_supported"
        case oldestWaiterStartedAt = "oldest_waiter_started_at"
        case oldestWaiterAgeMs = "oldest_waiter_age_ms"
        case contentionCount = "contention_count"
        case lastContentionAt = "last_contention_at"
        case activeMemoryBytes = "active_memory_bytes"
        case peakMemoryBytes = "peak_memory_bytes"
        case memoryState = "memory_state"
        case idleEvictionPolicy = "idle_eviction_policy"
        case lastIdleEvictionReason = "last_idle_eviction_reason"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        self.init(
            provider: (try? c.decode(String.self, forKey: .provider))
                ?? (try? s.decode(String.self, forKey: .provider))
                ?? "",
            ok: (try? c.decode(Bool.self, forKey: .ok))
                ?? (try? s.decode(Bool.self, forKey: .ok))
                ?? false,
            reasonCode: (try? c.decode(String.self, forKey: .reasonCode))
                ?? (try? s.decode(String.self, forKey: .reasonCode))
                ?? "",
            importError: (try? c.decode(String.self, forKey: .importError))
                ?? (try? s.decode(String.self, forKey: .importError))
                ?? "",
            runtimeSource: (try? c.decode(String.self, forKey: .runtimeSource))
                ?? (try? s.decode(String.self, forKey: .runtimeSource))
                ?? "",
            runtimeResolutionState: (try? c.decode(String.self, forKey: .runtimeResolutionState))
                ?? (try? s.decode(String.self, forKey: .runtimeResolutionState))
                ?? "",
            runtimeReasonCode: (try? c.decode(String.self, forKey: .runtimeReasonCode))
                ?? (try? s.decode(String.self, forKey: .runtimeReasonCode))
                ?? "",
            fallbackUsed: (try? c.decode(Bool.self, forKey: .fallbackUsed))
                ?? (try? s.decode(Bool.self, forKey: .fallbackUsed))
                ?? false,
            availableTaskKinds: (try? c.decode([String].self, forKey: .availableTaskKinds))
                ?? (try? s.decode([String].self, forKey: .availableTaskKinds))
                ?? [],
            realTaskKinds: (try? c.decode([String].self, forKey: .realTaskKinds))
                ?? (try? s.decode([String].self, forKey: .realTaskKinds))
                ?? [],
            fallbackTaskKinds: (try? c.decode([String].self, forKey: .fallbackTaskKinds))
                ?? (try? s.decode([String].self, forKey: .fallbackTaskKinds))
                ?? [],
            unavailableTaskKinds: (try? c.decode([String].self, forKey: .unavailableTaskKinds))
                ?? (try? s.decode([String].self, forKey: .unavailableTaskKinds))
                ?? [],
            deviceBackend: (try? c.decode(String.self, forKey: .deviceBackend))
                ?? (try? s.decode(String.self, forKey: .deviceBackend))
                ?? "",
            lifecycleMode: (try? c.decode(String.self, forKey: .lifecycleMode))
                ?? (try? s.decode(String.self, forKey: .lifecycleMode))
                ?? "",
            residencyScope: (try? c.decode(String.self, forKey: .residencyScope))
                ?? (try? s.decode(String.self, forKey: .residencyScope))
                ?? "",
            loadedInstanceCount: (try? c.decode(Int.self, forKey: .loadedInstanceCount))
                ?? (try? s.decode(Int.self, forKey: .loadedInstanceCount))
                ?? 0,
            loadedModelCount: (try? c.decode(Int.self, forKey: .loadedModelCount))
                ?? (try? s.decode(Int.self, forKey: .loadedModelCount))
                ?? 0,
            activeTaskCount: (try? c.decode(Int.self, forKey: .activeTaskCount))
                ?? (try? s.decode(Int.self, forKey: .activeTaskCount))
                ?? 0,
            queuedTaskCount: (try? c.decode(Int.self, forKey: .queuedTaskCount))
                ?? (try? s.decode(Int.self, forKey: .queuedTaskCount))
                ?? 0,
            concurrencyLimit: (try? c.decode(Int.self, forKey: .concurrencyLimit))
                ?? (try? s.decode(Int.self, forKey: .concurrencyLimit))
                ?? 1,
            queueMode: (try? c.decode(String.self, forKey: .queueMode))
                ?? (try? s.decode(String.self, forKey: .queueMode))
                ?? "",
            queueingSupported: (try? c.decode(Bool.self, forKey: .queueingSupported))
                ?? (try? s.decode(Bool.self, forKey: .queueingSupported))
                ?? false,
            oldestWaiterStartedAt: (try? c.decode(Double.self, forKey: .oldestWaiterStartedAt))
                ?? (try? s.decode(Double.self, forKey: .oldestWaiterStartedAt))
                ?? 0,
            oldestWaiterAgeMs: (try? c.decode(Int.self, forKey: .oldestWaiterAgeMs))
                ?? (try? s.decode(Int.self, forKey: .oldestWaiterAgeMs))
                ?? 0,
            contentionCount: (try? c.decode(Int.self, forKey: .contentionCount))
                ?? (try? s.decode(Int.self, forKey: .contentionCount))
                ?? 0,
            lastContentionAt: (try? c.decode(Double.self, forKey: .lastContentionAt))
                ?? (try? s.decode(Double.self, forKey: .lastContentionAt))
                ?? 0,
            activeMemoryBytes: (try? c.decode(Int64.self, forKey: .activeMemoryBytes))
                ?? (try? s.decode(Int64.self, forKey: .activeMemoryBytes))
                ?? 0,
            peakMemoryBytes: (try? c.decode(Int64.self, forKey: .peakMemoryBytes))
                ?? (try? s.decode(Int64.self, forKey: .peakMemoryBytes))
                ?? 0,
            memoryState: (try? c.decode(String.self, forKey: .memoryState))
                ?? (try? s.decode(String.self, forKey: .memoryState))
                ?? "",
            idleEvictionPolicy: (try? c.decode(String.self, forKey: .idleEvictionPolicy))
                ?? (try? s.decode(String.self, forKey: .idleEvictionPolicy))
                ?? "",
            lastIdleEvictionReason: (try? c.decode(String.self, forKey: .lastIdleEvictionReason))
                ?? (try? s.decode(String.self, forKey: .lastIdleEvictionReason))
                ?? "",
            updatedAt: (try? c.decode(Double.self, forKey: .updatedAt))
                ?? (try? s.decode(Double.self, forKey: .updatedAt))
                ?? 0
        )
    }
}

public struct AIRuntimeMonitorActiveTask: Codable, Sendable, Equatable {
    public var provider: String
    public var leaseId: String
    public var taskKind: String
    public var modelId: String
    public var requestId: String
    public var deviceId: String
    public var loadProfileHash: String
    public var instanceKey: String
    public var effectiveContextLength: Int
    public var maxContextLength: Int
    public var leaseTtlSec: Int?
    public var leaseRemainingTtlSec: Int?
    public var expiresAt: Double
    public var progress: Double?
    public var startedAt: Double

    public var loadConfigHash: String { loadProfileHash }
    public var currentContextLength: Int { effectiveContextLength }

    public init(
        provider: String,
        leaseId: String = "",
        taskKind: String = "",
        modelId: String = "",
        requestId: String = "",
        deviceId: String = "",
        loadProfileHash: String = "",
        instanceKey: String = "",
        effectiveContextLength: Int = 0,
        maxContextLength: Int = 0,
        leaseTtlSec: Int? = nil,
        leaseRemainingTtlSec: Int? = nil,
        expiresAt: Double = 0,
        progress: Double? = nil,
        startedAt: Double = 0
    ) {
        self.provider = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.leaseId = leaseId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.taskKind = taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.modelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.requestId = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.deviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.loadProfileHash = loadProfileHash.trimmingCharacters(in: .whitespacesAndNewlines)
        self.instanceKey = instanceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.effectiveContextLength = max(0, effectiveContextLength)
        self.maxContextLength = max(self.effectiveContextLength, max(0, maxContextLength))
        let normalizedStartedAt = max(0, startedAt)
        let normalizedExpiresAt = max(0, expiresAt)
        let derivedLeaseTtlSec: Int? = {
            guard normalizedExpiresAt > 0, normalizedStartedAt > 0, normalizedExpiresAt >= normalizedStartedAt else { return nil }
            return Int(round(normalizedExpiresAt - normalizedStartedAt))
        }()
        self.leaseTtlSec = Self.optionalPositiveInt(leaseTtlSec) ?? derivedLeaseTtlSec
        self.leaseRemainingTtlSec = Self.optionalNonNegativeInt(leaseRemainingTtlSec)
        self.expiresAt = normalizedExpiresAt
        self.progress = Self.normalizedProgress(progress)
        self.startedAt = normalizedStartedAt
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case leaseId
        case taskKind
        case modelId
        case requestId
        case deviceId
        case loadProfileHash
        case loadConfigHash
        case instanceKey
        case effectiveContextLength
        case currentContextLength
        case maxContextLength
        case leaseTtlSec
        case leaseRemainingTtlSec
        case expiresAt
        case progress
        case startedAt
    }

    enum SnakeCodingKeys: String, CodingKey {
        case provider
        case leaseId = "lease_id"
        case taskKind = "task_kind"
        case modelId = "model_id"
        case requestId = "request_id"
        case deviceId = "device_id"
        case loadProfileHash = "load_profile_hash"
        case loadConfigHash = "load_config_hash"
        case instanceKey = "instance_key"
        case effectiveContextLength = "effective_context_length"
        case currentContextLength = "current_context_length"
        case maxContextLength = "max_context_length"
        case leaseTtlSec = "lease_ttl_sec"
        case leaseRemainingTtlSec = "lease_remaining_ttl_sec"
        case expiresAt = "expires_at"
        case progress
        case startedAt = "started_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        self.init(
            provider: (try? c.decode(String.self, forKey: .provider))
                ?? (try? s.decode(String.self, forKey: .provider))
                ?? "",
            leaseId: (try? c.decode(String.self, forKey: .leaseId))
                ?? (try? s.decode(String.self, forKey: .leaseId))
                ?? "",
            taskKind: (try? c.decode(String.self, forKey: .taskKind))
                ?? (try? s.decode(String.self, forKey: .taskKind))
                ?? "",
            modelId: (try? c.decode(String.self, forKey: .modelId))
                ?? (try? s.decode(String.self, forKey: .modelId))
                ?? "",
            requestId: (try? c.decode(String.self, forKey: .requestId))
                ?? (try? s.decode(String.self, forKey: .requestId))
                ?? "",
            deviceId: (try? c.decode(String.self, forKey: .deviceId))
                ?? (try? s.decode(String.self, forKey: .deviceId))
                ?? "",
            loadProfileHash: (try? c.decode(String.self, forKey: .loadConfigHash))
                ?? (try? s.decode(String.self, forKey: .loadConfigHash))
                ?? (try? c.decode(String.self, forKey: .loadProfileHash))
                ?? (try? s.decode(String.self, forKey: .loadProfileHash))
                ?? "",
            instanceKey: (try? c.decode(String.self, forKey: .instanceKey))
                ?? (try? s.decode(String.self, forKey: .instanceKey))
                ?? "",
            effectiveContextLength: (try? c.decode(Int.self, forKey: .currentContextLength))
                ?? (try? s.decode(Int.self, forKey: .currentContextLength))
                ?? (try? c.decode(Int.self, forKey: .effectiveContextLength))
                ?? (try? s.decode(Int.self, forKey: .effectiveContextLength))
                ?? 0,
            maxContextLength: (try? c.decode(Int.self, forKey: .maxContextLength))
                ?? (try? s.decode(Int.self, forKey: .maxContextLength))
                ?? 0,
            leaseTtlSec: (try? c.decodeIfPresent(Int.self, forKey: .leaseTtlSec))
                ?? (try? s.decodeIfPresent(Int.self, forKey: .leaseTtlSec)),
            leaseRemainingTtlSec: (try? c.decodeIfPresent(Int.self, forKey: .leaseRemainingTtlSec))
                ?? (try? s.decodeIfPresent(Int.self, forKey: .leaseRemainingTtlSec)),
            expiresAt: (try? c.decode(Double.self, forKey: .expiresAt))
                ?? (try? s.decode(Double.self, forKey: .expiresAt))
                ?? 0,
            progress: (try? c.decodeIfPresent(Double.self, forKey: .progress))
                ?? (try? s.decodeIfPresent(Double.self, forKey: .progress)),
            startedAt: (try? c.decode(Double.self, forKey: .startedAt))
                ?? (try? s.decode(Double.self, forKey: .startedAt))
                ?? 0
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(provider, forKey: .provider)
        try c.encode(leaseId, forKey: .leaseId)
        try c.encode(taskKind, forKey: .taskKind)
        try c.encode(modelId, forKey: .modelId)
        try c.encode(requestId, forKey: .requestId)
        try c.encode(deviceId, forKey: .deviceId)
        try c.encode(loadProfileHash, forKey: .loadProfileHash)
        try c.encode(loadConfigHash, forKey: .loadConfigHash)
        try c.encode(instanceKey, forKey: .instanceKey)
        try c.encode(effectiveContextLength, forKey: .effectiveContextLength)
        try c.encode(currentContextLength, forKey: .currentContextLength)
        try c.encode(maxContextLength, forKey: .maxContextLength)
        try c.encodeIfPresent(leaseTtlSec, forKey: .leaseTtlSec)
        try c.encodeIfPresent(leaseRemainingTtlSec, forKey: .leaseRemainingTtlSec)
        try c.encode(expiresAt, forKey: .expiresAt)
        try c.encodeIfPresent(progress, forKey: .progress)
        try c.encode(startedAt, forKey: .startedAt)
    }

    private static func optionalPositiveInt(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func optionalNonNegativeInt(_ value: Int?) -> Int? {
        guard let value, value >= 0 else { return nil }
        return value
    }

    private static func normalizedProgress(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(1.0, max(0.0, value))
    }
}

public struct AIRuntimeMonitorQueueProvider: Codable, Sendable, Equatable {
    public var provider: String
    public var concurrencyLimit: Int
    public var activeTaskCount: Int
    public var queuedTaskCount: Int
    public var queueMode: String
    public var queueingSupported: Bool
    public var oldestWaiterStartedAt: Double
    public var oldestWaiterAgeMs: Int
    public var contentionCount: Int
    public var lastContentionAt: Double
    public var updatedAt: Double

    public init(
        provider: String,
        concurrencyLimit: Int = 1,
        activeTaskCount: Int = 0,
        queuedTaskCount: Int = 0,
        queueMode: String = "",
        queueingSupported: Bool = false,
        oldestWaiterStartedAt: Double = 0,
        oldestWaiterAgeMs: Int = 0,
        contentionCount: Int = 0,
        lastContentionAt: Double = 0,
        updatedAt: Double = 0
    ) {
        self.provider = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.concurrencyLimit = max(1, concurrencyLimit)
        self.activeTaskCount = max(0, activeTaskCount)
        self.queuedTaskCount = max(0, queuedTaskCount)
        self.queueMode = queueMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.queueingSupported = queueingSupported
        self.oldestWaiterStartedAt = max(0, oldestWaiterStartedAt)
        self.oldestWaiterAgeMs = max(0, oldestWaiterAgeMs)
        self.contentionCount = max(0, contentionCount)
        self.lastContentionAt = max(0, lastContentionAt)
        self.updatedAt = max(0, updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case concurrencyLimit
        case activeTaskCount
        case queuedTaskCount
        case queueMode
        case queueingSupported
        case oldestWaiterStartedAt
        case oldestWaiterAgeMs
        case contentionCount
        case lastContentionAt
        case updatedAt
    }

    enum SnakeCodingKeys: String, CodingKey {
        case provider
        case concurrencyLimit = "concurrency_limit"
        case activeTaskCount = "active_task_count"
        case queuedTaskCount = "queued_task_count"
        case queueMode = "queue_mode"
        case queueingSupported = "queueing_supported"
        case oldestWaiterStartedAt = "oldest_waiter_started_at"
        case oldestWaiterAgeMs = "oldest_waiter_age_ms"
        case contentionCount = "contention_count"
        case lastContentionAt = "last_contention_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        self.init(
            provider: (try? c.decode(String.self, forKey: .provider))
                ?? (try? s.decode(String.self, forKey: .provider))
                ?? "",
            concurrencyLimit: (try? c.decode(Int.self, forKey: .concurrencyLimit))
                ?? (try? s.decode(Int.self, forKey: .concurrencyLimit))
                ?? 1,
            activeTaskCount: (try? c.decode(Int.self, forKey: .activeTaskCount))
                ?? (try? s.decode(Int.self, forKey: .activeTaskCount))
                ?? 0,
            queuedTaskCount: (try? c.decode(Int.self, forKey: .queuedTaskCount))
                ?? (try? s.decode(Int.self, forKey: .queuedTaskCount))
                ?? 0,
            queueMode: (try? c.decode(String.self, forKey: .queueMode))
                ?? (try? s.decode(String.self, forKey: .queueMode))
                ?? "",
            queueingSupported: (try? c.decode(Bool.self, forKey: .queueingSupported))
                ?? (try? s.decode(Bool.self, forKey: .queueingSupported))
                ?? false,
            oldestWaiterStartedAt: (try? c.decode(Double.self, forKey: .oldestWaiterStartedAt))
                ?? (try? s.decode(Double.self, forKey: .oldestWaiterStartedAt))
                ?? 0,
            oldestWaiterAgeMs: (try? c.decode(Int.self, forKey: .oldestWaiterAgeMs))
                ?? (try? s.decode(Int.self, forKey: .oldestWaiterAgeMs))
                ?? 0,
            contentionCount: (try? c.decode(Int.self, forKey: .contentionCount))
                ?? (try? s.decode(Int.self, forKey: .contentionCount))
                ?? 0,
            lastContentionAt: (try? c.decode(Double.self, forKey: .lastContentionAt))
                ?? (try? s.decode(Double.self, forKey: .lastContentionAt))
                ?? 0,
            updatedAt: (try? c.decode(Double.self, forKey: .updatedAt))
                ?? (try? s.decode(Double.self, forKey: .updatedAt))
                ?? 0
        )
    }
}

public struct AIRuntimeMonitorQueue: Codable, Sendable, Equatable {
    public var providerCount: Int
    public var activeTaskCount: Int
    public var queuedTaskCount: Int
    public var providersBusyCount: Int
    public var providersWithQueuedTasksCount: Int
    public var maxOldestWaitMs: Int
    public var contentionCount: Int
    public var lastContentionAt: Double
    public var updatedAt: Double
    public var providers: [AIRuntimeMonitorQueueProvider]

    public init(
        providerCount: Int = 0,
        activeTaskCount: Int = 0,
        queuedTaskCount: Int = 0,
        providersBusyCount: Int = 0,
        providersWithQueuedTasksCount: Int = 0,
        maxOldestWaitMs: Int = 0,
        contentionCount: Int = 0,
        lastContentionAt: Double = 0,
        updatedAt: Double = 0,
        providers: [AIRuntimeMonitorQueueProvider] = []
    ) {
        self.providerCount = max(0, providerCount)
        self.activeTaskCount = max(0, activeTaskCount)
        self.queuedTaskCount = max(0, queuedTaskCount)
        self.providersBusyCount = max(0, providersBusyCount)
        self.providersWithQueuedTasksCount = max(0, providersWithQueuedTasksCount)
        self.maxOldestWaitMs = max(0, maxOldestWaitMs)
        self.contentionCount = max(0, contentionCount)
        self.lastContentionAt = max(0, lastContentionAt)
        self.updatedAt = max(0, updatedAt)
        self.providers = providers.sorted { $0.provider < $1.provider }
    }

    enum CodingKeys: String, CodingKey {
        case providerCount
        case activeTaskCount
        case queuedTaskCount
        case providersBusyCount
        case providersWithQueuedTasksCount
        case maxOldestWaitMs
        case contentionCount
        case lastContentionAt
        case updatedAt
        case providers
    }

    enum SnakeCodingKeys: String, CodingKey {
        case providerCount = "provider_count"
        case activeTaskCount = "active_task_count"
        case queuedTaskCount = "queued_task_count"
        case providersBusyCount = "providers_busy_count"
        case providersWithQueuedTasksCount = "providers_with_queued_tasks_count"
        case maxOldestWaitMs = "max_oldest_wait_ms"
        case contentionCount = "contention_count"
        case lastContentionAt = "last_contention_at"
        case updatedAt = "updated_at"
        case providers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        self.init(
            providerCount: (try? c.decode(Int.self, forKey: .providerCount))
                ?? (try? s.decode(Int.self, forKey: .providerCount))
                ?? 0,
            activeTaskCount: (try? c.decode(Int.self, forKey: .activeTaskCount))
                ?? (try? s.decode(Int.self, forKey: .activeTaskCount))
                ?? 0,
            queuedTaskCount: (try? c.decode(Int.self, forKey: .queuedTaskCount))
                ?? (try? s.decode(Int.self, forKey: .queuedTaskCount))
                ?? 0,
            providersBusyCount: (try? c.decode(Int.self, forKey: .providersBusyCount))
                ?? (try? s.decode(Int.self, forKey: .providersBusyCount))
                ?? 0,
            providersWithQueuedTasksCount: (try? c.decode(Int.self, forKey: .providersWithQueuedTasksCount))
                ?? (try? s.decode(Int.self, forKey: .providersWithQueuedTasksCount))
                ?? 0,
            maxOldestWaitMs: (try? c.decode(Int.self, forKey: .maxOldestWaitMs))
                ?? (try? s.decode(Int.self, forKey: .maxOldestWaitMs))
                ?? 0,
            contentionCount: (try? c.decode(Int.self, forKey: .contentionCount))
                ?? (try? s.decode(Int.self, forKey: .contentionCount))
                ?? 0,
            lastContentionAt: (try? c.decode(Double.self, forKey: .lastContentionAt))
                ?? (try? s.decode(Double.self, forKey: .lastContentionAt))
                ?? 0,
            updatedAt: (try? c.decode(Double.self, forKey: .updatedAt))
                ?? (try? s.decode(Double.self, forKey: .updatedAt))
                ?? 0,
            providers: (try? c.decode([AIRuntimeMonitorQueueProvider].self, forKey: .providers))
                ?? (try? s.decode([AIRuntimeMonitorQueueProvider].self, forKey: .providers))
                ?? []
        )
    }
}

public struct AIRuntimeMonitorLastError: Codable, Sendable, Equatable {
    public var provider: String
    public var code: String
    public var message: String
    public var severity: String
    public var updatedAt: Double

    public init(
        provider: String,
        code: String = "",
        message: String = "",
        severity: String = "",
        updatedAt: Double = 0
    ) {
        self.provider = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.code = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        self.severity = severity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.updatedAt = max(0, updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case code
        case message
        case severity
        case updatedAt
    }

    enum SnakeCodingKeys: String, CodingKey {
        case provider
        case code
        case message
        case severity
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        self.init(
            provider: (try? c.decode(String.self, forKey: .provider))
                ?? (try? s.decode(String.self, forKey: .provider))
                ?? "",
            code: (try? c.decode(String.self, forKey: .code))
                ?? (try? s.decode(String.self, forKey: .code))
                ?? "",
            message: (try? c.decode(String.self, forKey: .message))
                ?? (try? s.decode(String.self, forKey: .message))
                ?? "",
            severity: (try? c.decode(String.self, forKey: .severity))
                ?? (try? s.decode(String.self, forKey: .severity))
                ?? "",
            updatedAt: (try? c.decode(Double.self, forKey: .updatedAt))
                ?? (try? s.decode(Double.self, forKey: .updatedAt))
                ?? 0
        )
    }
}

public struct AIRuntimeMonitorFallbackCounters: Codable, Sendable, Equatable {
    public var providerCount: Int
    public var fallbackReadyProviderCount: Int
    public var fallbackOnlyProviderCount: Int
    public var fallbackReadyTaskCount: Int
    public var fallbackOnlyTaskCount: Int
    public var taskKindCounts: [String: Int]

    public init(
        providerCount: Int = 0,
        fallbackReadyProviderCount: Int = 0,
        fallbackOnlyProviderCount: Int = 0,
        fallbackReadyTaskCount: Int = 0,
        fallbackOnlyTaskCount: Int = 0,
        taskKindCounts: [String: Int] = [:]
    ) {
        self.providerCount = max(0, providerCount)
        self.fallbackReadyProviderCount = max(0, fallbackReadyProviderCount)
        self.fallbackOnlyProviderCount = max(0, fallbackOnlyProviderCount)
        self.fallbackReadyTaskCount = max(0, fallbackReadyTaskCount)
        self.fallbackOnlyTaskCount = max(0, fallbackOnlyTaskCount)
        var normalized: [String: Int] = [:]
        for (rawKey, rawValue) in taskKindCounts {
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            normalized[key] = max(0, rawValue)
        }
        self.taskKindCounts = normalized
    }

    enum CodingKeys: String, CodingKey {
        case providerCount
        case fallbackReadyProviderCount
        case fallbackOnlyProviderCount
        case fallbackReadyTaskCount
        case fallbackOnlyTaskCount
        case taskKindCounts
    }

    enum SnakeCodingKeys: String, CodingKey {
        case providerCount = "provider_count"
        case fallbackReadyProviderCount = "fallback_ready_provider_count"
        case fallbackOnlyProviderCount = "fallback_only_provider_count"
        case fallbackReadyTaskCount = "fallback_ready_task_count"
        case fallbackOnlyTaskCount = "fallback_only_task_count"
        case taskKindCounts = "task_kind_counts"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        self.init(
            providerCount: (try? c.decode(Int.self, forKey: .providerCount))
                ?? (try? s.decode(Int.self, forKey: .providerCount))
                ?? 0,
            fallbackReadyProviderCount: (try? c.decode(Int.self, forKey: .fallbackReadyProviderCount))
                ?? (try? s.decode(Int.self, forKey: .fallbackReadyProviderCount))
                ?? 0,
            fallbackOnlyProviderCount: (try? c.decode(Int.self, forKey: .fallbackOnlyProviderCount))
                ?? (try? s.decode(Int.self, forKey: .fallbackOnlyProviderCount))
                ?? 0,
            fallbackReadyTaskCount: (try? c.decode(Int.self, forKey: .fallbackReadyTaskCount))
                ?? (try? s.decode(Int.self, forKey: .fallbackReadyTaskCount))
                ?? 0,
            fallbackOnlyTaskCount: (try? c.decode(Int.self, forKey: .fallbackOnlyTaskCount))
                ?? (try? s.decode(Int.self, forKey: .fallbackOnlyTaskCount))
                ?? 0,
            taskKindCounts: (try? c.decode([String: Int].self, forKey: .taskKindCounts))
                ?? (try? s.decode([String: Int].self, forKey: .taskKindCounts))
                ?? [:]
        )
    }
}

public struct AIRuntimeRouteTraceSummary: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var traceSchemaVersion: String
    public var requestMode: String
    public var selectedTaskKind: String
    public var selectionReason: String
    public var explicitTaskKind: String
    public var imageCount: Int
    public var resolvedImageCount: Int
    public var blockedReasonCode: String
    public var blockedImageIndex: Int?
    public var promptChars: Int
    public var executionPath: String
    public var fallbackMode: String
    public var imageFiles: [String]

    public init(
        schemaVersion: String = "",
        traceSchemaVersion: String = "",
        requestMode: String = "",
        selectedTaskKind: String = "",
        selectionReason: String = "",
        explicitTaskKind: String = "",
        imageCount: Int = 0,
        resolvedImageCount: Int = 0,
        blockedReasonCode: String = "",
        blockedImageIndex: Int? = nil,
        promptChars: Int = 0,
        executionPath: String = "",
        fallbackMode: String = "",
        imageFiles: [String] = []
    ) {
        self.schemaVersion = schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        self.traceSchemaVersion = traceSchemaVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        self.requestMode = requestMode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.selectedTaskKind = selectedTaskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.selectionReason = selectionReason.trimmingCharacters(in: .whitespacesAndNewlines)
        self.explicitTaskKind = explicitTaskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.imageCount = max(0, imageCount)
        self.resolvedImageCount = max(0, resolvedImageCount)
        self.blockedReasonCode = blockedReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if let blockedImageIndex {
            self.blockedImageIndex = max(0, blockedImageIndex)
        } else {
            self.blockedImageIndex = nil
        }
        self.promptChars = max(0, promptChars)
        self.executionPath = executionPath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fallbackMode = fallbackMode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.imageFiles = AIRuntimeRouteTraceSummary.normalizedImageFiles(imageFiles)
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case traceSchemaVersion
        case requestMode
        case selectedTaskKind
        case selectionReason
        case explicitTaskKind
        case imageCount
        case resolvedImageCount
        case blockedReasonCode
        case blockedImageIndex
        case promptChars
        case executionPath
        case fallbackMode
        case imageFiles
    }

    enum SnakeCodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case traceSchemaVersion = "trace_schema_version"
        case requestMode = "request_mode"
        case selectedTaskKind = "selected_task_kind"
        case selectionReason = "selection_reason"
        case explicitTaskKind = "explicit_task_kind"
        case imageCount = "image_count"
        case resolvedImageCount = "resolved_image_count"
        case blockedReasonCode = "blocked_reason_code"
        case blockedImageIndex = "blocked_image_index"
        case promptChars = "prompt_chars"
        case executionPath = "execution_path"
        case fallbackMode = "fallback_mode"
        case imageFiles = "image_files"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        self.init(
            schemaVersion: (try? c.decode(String.self, forKey: .schemaVersion))
                ?? (try? s.decode(String.self, forKey: .schemaVersion))
                ?? "",
            traceSchemaVersion: (try? c.decode(String.self, forKey: .traceSchemaVersion))
                ?? (try? s.decode(String.self, forKey: .traceSchemaVersion))
                ?? "",
            requestMode: (try? c.decode(String.self, forKey: .requestMode))
                ?? (try? s.decode(String.self, forKey: .requestMode))
                ?? "",
            selectedTaskKind: (try? c.decode(String.self, forKey: .selectedTaskKind))
                ?? (try? s.decode(String.self, forKey: .selectedTaskKind))
                ?? "",
            selectionReason: (try? c.decode(String.self, forKey: .selectionReason))
                ?? (try? s.decode(String.self, forKey: .selectionReason))
                ?? "",
            explicitTaskKind: (try? c.decode(String.self, forKey: .explicitTaskKind))
                ?? (try? s.decode(String.self, forKey: .explicitTaskKind))
                ?? "",
            imageCount: (try? c.decode(Int.self, forKey: .imageCount))
                ?? (try? s.decode(Int.self, forKey: .imageCount))
                ?? 0,
            resolvedImageCount: (try? c.decode(Int.self, forKey: .resolvedImageCount))
                ?? (try? s.decode(Int.self, forKey: .resolvedImageCount))
                ?? 0,
            blockedReasonCode: (try? c.decode(String.self, forKey: .blockedReasonCode))
                ?? (try? s.decode(String.self, forKey: .blockedReasonCode))
                ?? "",
            blockedImageIndex: (try? c.decodeIfPresent(Int.self, forKey: .blockedImageIndex))
                ?? (try? s.decodeIfPresent(Int.self, forKey: .blockedImageIndex)),
            promptChars: (try? c.decode(Int.self, forKey: .promptChars))
                ?? (try? s.decode(Int.self, forKey: .promptChars))
                ?? 0,
            executionPath: (try? c.decode(String.self, forKey: .executionPath))
                ?? (try? s.decode(String.self, forKey: .executionPath))
                ?? "",
            fallbackMode: (try? c.decode(String.self, forKey: .fallbackMode))
                ?? (try? s.decode(String.self, forKey: .fallbackMode))
                ?? "",
            imageFiles: (try? c.decode([String].self, forKey: .imageFiles))
                ?? (try? s.decode([String].self, forKey: .imageFiles))
                ?? []
        )
    }

    private static func normalizedImageFiles(_ values: [String]) -> [String] {
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

public struct AIRuntimeMonitorSnapshot: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var updatedAt: Double
    public var providers: [AIRuntimeMonitorProvider]
    public var activeTasks: [AIRuntimeMonitorActiveTask]
    public var loadedInstances: [AIRuntimeLoadedInstance]
    public var recentBenchResults: [ModelBenchResult]
    public var queue: AIRuntimeMonitorQueue
    public var lastErrors: [AIRuntimeMonitorLastError]
    public var fallbackCounters: AIRuntimeMonitorFallbackCounters

    public init(
        schemaVersion: String = "",
        updatedAt: Double = 0,
        providers: [AIRuntimeMonitorProvider] = [],
        activeTasks: [AIRuntimeMonitorActiveTask] = [],
        loadedInstances: [AIRuntimeLoadedInstance] = [],
        recentBenchResults: [ModelBenchResult] = [],
        queue: AIRuntimeMonitorQueue = AIRuntimeMonitorQueue(),
        lastErrors: [AIRuntimeMonitorLastError] = [],
        fallbackCounters: AIRuntimeMonitorFallbackCounters = AIRuntimeMonitorFallbackCounters()
    ) {
        self.schemaVersion = schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        self.updatedAt = max(0, updatedAt)
        self.providers = providers.sorted { $0.provider < $1.provider }
        self.activeTasks = activeTasks.sorted {
            if $0.provider == $1.provider {
                if $0.taskKind == $1.taskKind {
                    if $0.modelId == $1.modelId {
                        return $0.leaseId < $1.leaseId
                    }
                    return $0.modelId < $1.modelId
                }
                return $0.taskKind < $1.taskKind
            }
            return $0.provider < $1.provider
        }
        self.loadedInstances = loadedInstances.sorted {
            if $0.modelId == $1.modelId {
                return $0.instanceKey < $1.instanceKey
            }
            return $0.modelId < $1.modelId
        }
        self.recentBenchResults = AIRuntimeMonitorSnapshot.normalizedRecentBenchResults(recentBenchResults)
        self.queue = queue
        self.lastErrors = lastErrors.sorted {
            if $0.provider == $1.provider {
                return $0.code < $1.code
            }
            return $0.provider < $1.provider
        }
        self.fallbackCounters = fallbackCounters
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case updatedAt
        case providers
        case activeTasks
        case loadedInstances
        case recentBenchResults
        case queue
        case lastErrors
        case fallbackCounters
    }

    enum SnakeCodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAt = "updated_at"
        case providers
        case activeTasks = "active_tasks"
        case loadedInstances = "loaded_instances"
        case recentBenchResults = "recent_bench_results"
        case queue
        case lastErrors = "last_errors"
        case fallbackCounters = "fallback_counters"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        self.init(
            schemaVersion: (try? c.decode(String.self, forKey: .schemaVersion))
                ?? (try? s.decode(String.self, forKey: .schemaVersion))
                ?? "",
            updatedAt: (try? c.decode(Double.self, forKey: .updatedAt))
                ?? (try? s.decode(Double.self, forKey: .updatedAt))
                ?? 0,
            providers: (try? c.decode([AIRuntimeMonitorProvider].self, forKey: .providers))
                ?? (try? s.decode([AIRuntimeMonitorProvider].self, forKey: .providers))
                ?? [],
            activeTasks: (try? c.decode([AIRuntimeMonitorActiveTask].self, forKey: .activeTasks))
                ?? (try? s.decode([AIRuntimeMonitorActiveTask].self, forKey: .activeTasks))
                ?? [],
            loadedInstances: (try? c.decode([AIRuntimeLoadedInstance].self, forKey: .loadedInstances))
                ?? (try? s.decode([AIRuntimeLoadedInstance].self, forKey: .loadedInstances))
                ?? [],
            recentBenchResults: (try? c.decode([ModelBenchResult].self, forKey: .recentBenchResults))
                ?? (try? s.decode([ModelBenchResult].self, forKey: .recentBenchResults))
                ?? [],
            queue: (try? c.decode(AIRuntimeMonitorQueue.self, forKey: .queue))
                ?? (try? s.decode(AIRuntimeMonitorQueue.self, forKey: .queue))
                ?? AIRuntimeMonitorQueue(),
            lastErrors: (try? c.decode([AIRuntimeMonitorLastError].self, forKey: .lastErrors))
                ?? (try? s.decode([AIRuntimeMonitorLastError].self, forKey: .lastErrors))
                ?? [],
            fallbackCounters: (try? c.decode(AIRuntimeMonitorFallbackCounters.self, forKey: .fallbackCounters))
                ?? (try? s.decode(AIRuntimeMonitorFallbackCounters.self, forKey: .fallbackCounters))
                ?? AIRuntimeMonitorFallbackCounters()
        )
    }

    private static func normalizedRecentBenchResults(_ values: [ModelBenchResult]) -> [ModelBenchResult] {
        var out: [String: ModelBenchResult] = [:]
        for value in values {
            let key = value.id
            if key.isEmpty {
                continue
            }
            if let existing = out[key], existing.measuredAt > value.measuredAt {
                continue
            }
            out[key] = value
        }
        return out.values.sorted {
            if $0.measuredAt == $1.measuredAt {
                return $0.id < $1.id
            }
            return $0.measuredAt > $1.measuredAt
        }
    }
}

public struct AIRuntimeProviderStatus: Codable, Sendable, Equatable {
    public var provider: String
    public var ok: Bool
    public var reasonCode: String?
    public var runtimeVersion: String?
    public var runtimeSource: String
    public var runtimeSourcePath: String
    public var runtimeResolutionState: String
    public var runtimeReasonCode: String
    public var fallbackUsed: Bool
    public var runtimeHint: String
    public var runtimeMissingRequirements: [String]
    public var runtimeMissingOptionalRequirements: [String]
    public var availableTaskKinds: [String]
    public var loadedModels: [String]
    public var deviceBackend: String?
    public var updatedAt: Double
    public var importError: String?
    public var activeMemoryBytes: Int64?
    public var peakMemoryBytes: Int64?
    public var loadedModelCount: Int?
    public var lifecycleMode: String
    public var supportedLifecycleActions: [String]
    public var warmupTaskKinds: [String]
    public var residencyScope: String
    public var loadedInstances: [AIRuntimeLoadedInstance]
    public var packId: String
    public var packEngine: String
    public var packVersion: String
    public var packInstalled: Bool
    public var packEnabled: Bool
    public var packState: String
    public var packReasonCode: String
    public var managedServiceState: AIRuntimeManagedServiceState?

    public init(
        provider: String,
        ok: Bool,
        reasonCode: String? = nil,
        runtimeVersion: String? = nil,
        runtimeSource: String = "",
        runtimeSourcePath: String = "",
        runtimeResolutionState: String = "",
        runtimeReasonCode: String = "",
        fallbackUsed: Bool = false,
        runtimeHint: String = "",
        runtimeMissingRequirements: [String] = [],
        runtimeMissingOptionalRequirements: [String] = [],
        availableTaskKinds: [String] = [],
        loadedModels: [String] = [],
        deviceBackend: String? = nil,
        updatedAt: Double = 0,
        importError: String? = nil,
        activeMemoryBytes: Int64? = nil,
        peakMemoryBytes: Int64? = nil,
        loadedModelCount: Int? = nil,
        lifecycleMode: String = "",
        supportedLifecycleActions: [String] = [],
        warmupTaskKinds: [String] = [],
        residencyScope: String = "",
        loadedInstances: [AIRuntimeLoadedInstance] = [],
        packId: String = "",
        packEngine: String = "",
        packVersion: String = "",
        packInstalled: Bool = false,
        packEnabled: Bool = false,
        packState: String = "",
        packReasonCode: String = "",
        managedServiceState: AIRuntimeManagedServiceState? = nil
    ) {
        self.provider = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.ok = ok
        self.reasonCode = reasonCode
        self.runtimeVersion = runtimeVersion
        self.runtimeSource = runtimeSource.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.runtimeSourcePath = runtimeSourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.runtimeResolutionState = runtimeResolutionState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.runtimeReasonCode = runtimeReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fallbackUsed = fallbackUsed
        self.runtimeHint = runtimeHint.trimmingCharacters(in: .whitespacesAndNewlines)
        self.runtimeMissingRequirements = LocalModelCapabilityDefaults.normalizedStringList(
            runtimeMissingRequirements,
            fallback: []
        )
        self.runtimeMissingOptionalRequirements = LocalModelCapabilityDefaults.normalizedStringList(
            runtimeMissingOptionalRequirements,
            fallback: []
        )
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
        self.lifecycleMode = lifecycleMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.supportedLifecycleActions = LocalModelCapabilityDefaults.normalizedStringList(
            supportedLifecycleActions,
            fallback: []
        )
        self.warmupTaskKinds = LocalModelCapabilityDefaults.normalizedStringList(
            warmupTaskKinds,
            fallback: []
        )
        self.residencyScope = residencyScope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.loadedInstances = AIRuntimeProviderStatus.normalizedLoadedInstances(loadedInstances)
        self.packId = packId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.packEngine = packEngine.trimmingCharacters(in: .whitespacesAndNewlines)
        self.packVersion = packVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        self.packInstalled = packInstalled
        self.packEnabled = packEnabled
        self.packState = packState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.packReasonCode = packReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.managedServiceState = managedServiceState
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case ok
        case reasonCode
        case runtimeVersion
        case runtimeSource
        case runtimeSourcePath
        case runtimeResolutionState
        case runtimeReasonCode
        case fallbackUsed
        case runtimeHint
        case runtimeMissingRequirements
        case runtimeMissingOptionalRequirements
        case availableTaskKinds
        case loadedModels
        case deviceBackend
        case updatedAt
        case importError
        case activeMemoryBytes
        case peakMemoryBytes
        case loadedModelCount
        case lifecycleMode
        case supportedLifecycleActions
        case warmupTaskKinds
        case residencyScope
        case loadedInstances
        case packId
        case packEngine
        case packVersion
        case packInstalled
        case packEnabled
        case packState
        case packReasonCode
        case managedServiceState
    }

    enum SnakeCodingKeys: String, CodingKey {
        case provider
        case ok
        case reasonCode = "reason_code"
        case runtimeVersion = "runtime_version"
        case runtimeSource = "runtime_source"
        case runtimeSourcePath = "runtime_source_path"
        case runtimeResolutionState = "runtime_resolution_state"
        case runtimeReasonCode = "runtime_reason_code"
        case fallbackUsed = "fallback_used"
        case runtimeHint = "runtime_hint"
        case runtimeMissingRequirements = "runtime_missing_requirements"
        case runtimeMissingOptionalRequirements = "runtime_missing_optional_requirements"
        case availableTaskKinds = "available_task_kinds"
        case loadedModels = "loaded_models"
        case deviceBackend = "device_backend"
        case updatedAt = "updated_at"
        case importError = "import_error"
        case activeMemoryBytes = "active_memory_bytes"
        case peakMemoryBytes = "peak_memory_bytes"
        case loadedModelCount = "loaded_model_count"
        case lifecycleMode = "lifecycle_mode"
        case supportedLifecycleActions = "supported_lifecycle_actions"
        case warmupTaskKinds = "warmup_task_kinds"
        case residencyScope = "residency_scope"
        case loadedInstances = "loaded_instances"
        case packId = "pack_id"
        case packEngine = "pack_engine"
        case packVersion = "pack_version"
        case packInstalled = "pack_installed"
        case packEnabled = "pack_enabled"
        case packState = "pack_state"
        case packReasonCode = "pack_reason_code"
        case managedServiceState = "managed_service_state"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        self.init(
            provider: (try? c.decode(String.self, forKey: .provider))
                ?? (try? s.decode(String.self, forKey: .provider))
                ?? "unknown",
            ok: (try? c.decode(Bool.self, forKey: .ok))
                ?? (try? s.decode(Bool.self, forKey: .ok))
                ?? false,
            reasonCode: (try? c.decodeIfPresent(String.self, forKey: .reasonCode))
                ?? (try? s.decodeIfPresent(String.self, forKey: .reasonCode)),
            runtimeVersion: (try? c.decodeIfPresent(String.self, forKey: .runtimeVersion))
                ?? (try? s.decodeIfPresent(String.self, forKey: .runtimeVersion)),
            runtimeSource: (try? c.decode(String.self, forKey: .runtimeSource))
                ?? (try? s.decode(String.self, forKey: .runtimeSource))
                ?? "",
            runtimeSourcePath: (try? c.decode(String.self, forKey: .runtimeSourcePath))
                ?? (try? s.decode(String.self, forKey: .runtimeSourcePath))
                ?? "",
            runtimeResolutionState: (try? c.decode(String.self, forKey: .runtimeResolutionState))
                ?? (try? s.decode(String.self, forKey: .runtimeResolutionState))
                ?? "",
            runtimeReasonCode: (try? c.decode(String.self, forKey: .runtimeReasonCode))
                ?? (try? s.decode(String.self, forKey: .runtimeReasonCode))
                ?? "",
            fallbackUsed: (try? c.decode(Bool.self, forKey: .fallbackUsed))
                ?? (try? s.decode(Bool.self, forKey: .fallbackUsed))
                ?? false,
            runtimeHint: (try? c.decode(String.self, forKey: .runtimeHint))
                ?? (try? s.decode(String.self, forKey: .runtimeHint))
                ?? "",
            runtimeMissingRequirements: (try? c.decode([String].self, forKey: .runtimeMissingRequirements))
                ?? (try? s.decode([String].self, forKey: .runtimeMissingRequirements))
                ?? [],
            runtimeMissingOptionalRequirements: (try? c.decode([String].self, forKey: .runtimeMissingOptionalRequirements))
                ?? (try? s.decode([String].self, forKey: .runtimeMissingOptionalRequirements))
                ?? [],
            availableTaskKinds: (try? c.decode([String].self, forKey: .availableTaskKinds))
                ?? (try? s.decode([String].self, forKey: .availableTaskKinds))
                ?? [],
            loadedModels: (try? c.decode([String].self, forKey: .loadedModels))
                ?? (try? s.decode([String].self, forKey: .loadedModels))
                ?? [],
            deviceBackend: (try? c.decodeIfPresent(String.self, forKey: .deviceBackend))
                ?? (try? s.decodeIfPresent(String.self, forKey: .deviceBackend)),
            updatedAt: (try? c.decode(Double.self, forKey: .updatedAt))
                ?? (try? s.decode(Double.self, forKey: .updatedAt))
                ?? 0,
            importError: (try? c.decodeIfPresent(String.self, forKey: .importError))
                ?? (try? s.decodeIfPresent(String.self, forKey: .importError)),
            activeMemoryBytes: (try? c.decodeIfPresent(Int64.self, forKey: .activeMemoryBytes))
                ?? (try? s.decodeIfPresent(Int64.self, forKey: .activeMemoryBytes)),
            peakMemoryBytes: (try? c.decodeIfPresent(Int64.self, forKey: .peakMemoryBytes))
                ?? (try? s.decodeIfPresent(Int64.self, forKey: .peakMemoryBytes)),
            loadedModelCount: (try? c.decodeIfPresent(Int.self, forKey: .loadedModelCount))
                ?? (try? s.decodeIfPresent(Int.self, forKey: .loadedModelCount)),
            lifecycleMode: (try? c.decode(String.self, forKey: .lifecycleMode))
                ?? (try? s.decode(String.self, forKey: .lifecycleMode))
                ?? "",
            supportedLifecycleActions: (try? c.decode([String].self, forKey: .supportedLifecycleActions))
                ?? (try? s.decode([String].self, forKey: .supportedLifecycleActions))
                ?? [],
            warmupTaskKinds: (try? c.decode([String].self, forKey: .warmupTaskKinds))
                ?? (try? s.decode([String].self, forKey: .warmupTaskKinds))
                ?? [],
            residencyScope: (try? c.decode(String.self, forKey: .residencyScope))
                ?? (try? s.decode(String.self, forKey: .residencyScope))
                ?? "",
            loadedInstances: (try? c.decode([AIRuntimeLoadedInstance].self, forKey: .loadedInstances))
                ?? (try? s.decode([AIRuntimeLoadedInstance].self, forKey: .loadedInstances))
                ?? [],
            packId: (try? c.decode(String.self, forKey: .packId))
                ?? (try? s.decode(String.self, forKey: .packId))
                ?? "",
            packEngine: (try? c.decode(String.self, forKey: .packEngine))
                ?? (try? s.decode(String.self, forKey: .packEngine))
                ?? "",
            packVersion: (try? c.decode(String.self, forKey: .packVersion))
                ?? (try? s.decode(String.self, forKey: .packVersion))
                ?? "",
            packInstalled: (try? c.decode(Bool.self, forKey: .packInstalled))
                ?? (try? s.decode(Bool.self, forKey: .packInstalled))
                ?? false,
            packEnabled: (try? c.decode(Bool.self, forKey: .packEnabled))
                ?? (try? s.decode(Bool.self, forKey: .packEnabled))
                ?? false,
            packState: (try? c.decode(String.self, forKey: .packState))
                ?? (try? s.decode(String.self, forKey: .packState))
                ?? "",
            packReasonCode: (try? c.decode(String.self, forKey: .packReasonCode))
                ?? (try? s.decode(String.self, forKey: .packReasonCode))
                ?? "",
            managedServiceState: (try? c.decodeIfPresent(AIRuntimeManagedServiceState.self, forKey: .managedServiceState))
                ?? (try? s.decodeIfPresent(AIRuntimeManagedServiceState.self, forKey: .managedServiceState))
        )
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

    private static func normalizedLoadedInstances(_ values: [AIRuntimeLoadedInstance]) -> [AIRuntimeLoadedInstance] {
        var out: [AIRuntimeLoadedInstance] = []
        var seen: Set<String> = []
        for value in values {
            if value.instanceKey.isEmpty || seen.contains(value.instanceKey) {
                continue
            }
            seen.insert(value.instanceKey)
            out.append(value)
        }
        return out.sorted {
            if $0.modelId == $1.modelId {
                return $0.instanceKey < $1.instanceKey
            }
            return $0.modelId < $1.modelId
        }
    }

    public func supportsLifecycleAction(_ action: AIRuntimeProviderLifecycleAction) -> Bool {
        let supported = Set(
            supportedLifecycleActions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        switch action {
        case .warmupLocalModel:
            return supported.contains(action.rawValue) || supported.contains("warmup")
        case .unloadLocalModel:
            return supported.contains(action.rawValue) || supported.contains("unload")
        case .evictLocalInstance:
            return supported.contains(action.rawValue) || supported.contains("evict")
        }
    }

    public func supportsWarmup(forModelTaskKinds taskKinds: [String]) -> Bool {
        guard supportsLifecycleAction(.warmupLocalModel) else { return false }
        if warmupTaskKinds.isEmpty {
            return true
        }
        return !Set(warmupTaskKinds).isDisjoint(with: Set(LocalModelCapabilityDefaults.normalizedStringList(taskKinds, fallback: [])))
    }

    public func hubControlMode(forModelTaskKinds taskKinds: [String]) -> AIRuntimeProviderHubControlMode {
        if lifecycleMode == AIRuntimeProviderHubControlMode.mlxLegacy.rawValue || provider == "mlx" {
            return .mlxLegacy
        }
        if residencyScope == "process_local" || lifecycleMode == AIRuntimeProviderHubControlMode.ephemeralOnDemand.rawValue {
            return .ephemeralOnDemand
        }
        if supportsWarmup(forModelTaskKinds: taskKinds) {
            return .warmable
        }
        return .ephemeralOnDemand
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
    public var providerPacks: [AIRuntimeProviderPackStatus]
    public var monitorSnapshot: AIRuntimeMonitorSnapshot?

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
        providers: [String: AIRuntimeProviderStatus] = [:],
        providerPacks: [AIRuntimeProviderPackStatus] = [],
        monitorSnapshot: AIRuntimeMonitorSnapshot? = nil
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
        self.providerPacks = AIRuntimeStatus.normalizedProviderPacks(
            providerPacks,
            providers: normalizedProviders
        )
        self.providers = AIRuntimeStatus.backfilledProviders(
            normalizedProviders,
            providerPacks: self.providerPacks
        )
        self.mlxOk = normalizedProviders["mlx"]?.ok ?? mlxOk
        self.monitorSnapshot = monitorSnapshot
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
        case providerPacks
        case monitorSnapshot
    }

    enum SnakeCodingKeys: String, CodingKey {
        case pid
        case updatedAt = "updated_at"
        case schemaVersion = "schemaVersion"
        case mlxOk = "mlx_ok"
        case runtimeVersion = "runtime_version"
        case importError = "import_error"
        case activeMemoryBytes = "active_memory_bytes"
        case peakMemoryBytes = "peak_memory_bytes"
        case loadedModelCount = "loaded_model_count"
        case providers
        case providerPacks = "provider_packs"
        case monitorSnapshot = "monitor_snapshot"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        let legacyPid = (try? c.decode(Int.self, forKey: .pid))
            ?? (try? s.decode(Int.self, forKey: .pid))
            ?? 0
        let legacyUpdatedAt = (try? c.decode(Double.self, forKey: .updatedAt))
            ?? (try? s.decode(Double.self, forKey: .updatedAt))
            ?? 0
        let legacyMlxOk = (try? c.decode(Bool.self, forKey: .mlxOk))
            ?? (try? s.decode(Bool.self, forKey: .mlxOk))
            ?? false
        let legacyRuntimeVersion = (try? c.decodeIfPresent(String.self, forKey: .runtimeVersion))
            ?? (try? s.decodeIfPresent(String.self, forKey: .runtimeVersion))
        let legacyImportError = (try? c.decodeIfPresent(String.self, forKey: .importError))
            ?? (try? s.decodeIfPresent(String.self, forKey: .importError))
        let legacyActiveMemoryBytes = (try? c.decodeIfPresent(Int64.self, forKey: .activeMemoryBytes))
            ?? (try? s.decodeIfPresent(Int64.self, forKey: .activeMemoryBytes))
        let legacyPeakMemoryBytes = (try? c.decodeIfPresent(Int64.self, forKey: .peakMemoryBytes))
            ?? (try? s.decodeIfPresent(Int64.self, forKey: .peakMemoryBytes))
        let legacyLoadedModelCount = (try? c.decodeIfPresent(Int.self, forKey: .loadedModelCount))
            ?? (try? s.decodeIfPresent(Int.self, forKey: .loadedModelCount))
        let decodedProviders = (try? c.decode([String: AIRuntimeProviderStatus].self, forKey: .providers))
            ?? (try? s.decode([String: AIRuntimeProviderStatus].self, forKey: .providers))
            ?? [:]
        let decodedProviderPacks = (try? c.decode([AIRuntimeProviderPackStatus].self, forKey: .providerPacks))
            ?? (try? s.decode([AIRuntimeProviderPackStatus].self, forKey: .providerPacks))
            ?? []

        pid = legacyPid
        updatedAt = legacyUpdatedAt
        schemaVersion = (try? c.decodeIfPresent(String.self, forKey: .schemaVersion))
            ?? (try? s.decodeIfPresent(String.self, forKey: .schemaVersion))
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
        providerPacks = AIRuntimeStatus.normalizedProviderPacks(
            decodedProviderPacks,
            providers: providers
        )
        providers = AIRuntimeStatus.backfilledProviders(
            providers,
            providerPacks: providerPacks
        )
        let mlxProvider = providers["mlx"]
        mlxOk = mlxProvider?.ok ?? legacyMlxOk
        runtimeVersion = legacyRuntimeVersion ?? mlxProvider?.runtimeVersion
        importError = legacyImportError ?? mlxProvider?.importError
        activeMemoryBytes = legacyActiveMemoryBytes ?? mlxProvider?.activeMemoryBytes
        peakMemoryBytes = legacyPeakMemoryBytes ?? mlxProvider?.peakMemoryBytes
        loadedModelCount = legacyLoadedModelCount ?? mlxProvider?.loadedModelCount
        monitorSnapshot = (try? c.decodeIfPresent(AIRuntimeMonitorSnapshot.self, forKey: .monitorSnapshot))
            ?? (try? s.decodeIfPresent(AIRuntimeMonitorSnapshot.self, forKey: .monitorSnapshot))
    }

    public func isAlive(ttl: Double = AIRuntimeStatus.recommendedHeartbeatTTL) -> Bool {
        (Date().timeIntervalSince1970 - updatedAt) < ttl
    }

    public func providerStatus(_ providerID: String) -> AIRuntimeProviderStatus? {
        providers[providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    public func providerPackStatus(_ providerID: String) -> AIRuntimeProviderPackStatus? {
        let key = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return providerPacks.first { $0.providerId == key }
    }

    public func isProviderReady(_ providerID: String, ttl: Double = AIRuntimeStatus.recommendedHeartbeatTTL) -> Bool {
        guard isAlive(ttl: ttl) else { return false }
        return providerStatus(providerID)?.ok ?? false
    }

    public func readyProviderIDs(ttl: Double = AIRuntimeStatus.recommendedHeartbeatTTL) -> [String] {
        guard isAlive(ttl: ttl) else { return [] }
        return providers.values
            .filter { $0.ok }
            .map(\.provider)
            .sorted()
    }

    public func hasReadyProvider(ttl: Double = AIRuntimeStatus.recommendedHeartbeatTTL) -> Bool {
        !readyProviderIDs(ttl: ttl).isEmpty
    }

    public func providerSummary(ttl: Double = AIRuntimeStatus.recommendedHeartbeatTTL) -> String {
        let ready = readyProviderIDs(ttl: ttl)
        return ready.isEmpty ? "none" : ready.joined(separator: ",")
    }

    public func providerDiagnoses(ttl: Double = AIRuntimeStatus.recommendedHeartbeatTTL) -> [AIRuntimeProviderDiagnosis] {
        let runtimeAlive = isAlive(ttl: ttl)
        return providers.keys.sorted().compactMap { key in
            guard let status = providers[key] else { return nil }
            return AIRuntimeProviderDiagnosis(
                provider: key,
                state: runtimeAlive ? (status.ok ? .ready : .down) : .stale,
                reasonCode: (status.reasonCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                runtimeVersion: (status.runtimeVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                runtimeSource: status.runtimeSource,
                runtimeSourcePath: status.runtimeSourcePath,
                runtimeResolutionState: status.runtimeResolutionState,
                runtimeReasonCode: status.runtimeReasonCode,
                fallbackUsed: status.fallbackUsed,
                availableTaskKinds: LocalModelCapabilityDefaults.normalizedStringList(
                    status.availableTaskKinds,
                    fallback: []
                ),
                loadedModels: status.loadedModels,
                deviceBackend: (status.deviceBackend ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                importError: (status.importError ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                loadedModelCount: status.loadedModelCount ?? status.loadedModels.count,
                managedServiceState: status.managedServiceState
            )
        }
    }

    public func localCapabilityDiagnoses(
        ttl: Double = AIRuntimeStatus.recommendedHeartbeatTTL,
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
        ttl: Double = AIRuntimeStatus.recommendedHeartbeatTTL,
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
        let recentBenchResults = monitorSnapshot?.recentBenchResults ?? []
        lines.append("ready_providers=\(readyProviders.isEmpty ? "none" : readyProviders.joined(separator: ","))")
        lines.append("provider_pack_count=\(providerPacks.count)")
        lines.append("providers:")
        for diagnosis in diagnoses {
            lines.append(AIRuntimeStatus.providerDiagnosisLine(diagnosis))
        }
        lines.append("provider_packs:")
        if providerPacks.isEmpty {
            lines.append("(none)")
        } else {
            for pack in providerPacks.sorted(by: { $0.providerId < $1.providerId }) {
                let engine = pack.engine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : pack.engine
                let version = pack.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : pack.version
                let state = pack.packState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : pack.packState
                let reason = pack.reasonCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "none" : pack.reasonCode
                let formats = pack.supportedFormats.isEmpty ? "(none)" : pack.supportedFormats.joined(separator: ",")
                let domains = pack.supportedDomains.isEmpty ? "(none)" : pack.supportedDomains.joined(separator: ",")
                lines.append(
                    "provider=\(pack.providerId) installed=\(pack.installed ? "1" : "0") enabled=\(pack.enabled ? "1" : "0") state=\(state) engine=\(engine) version=\(version) formats=\(formats) domains=\(domains) reason=\(reason)"
                )
            }
        }
        lines.append("capabilities:")
        for capability in capabilities {
            let providers = capability.providerIDs.isEmpty ? "none" : capability.providerIDs.joined(separator: ",")
            lines.append(
                "capability=\(capability.capabilityKey) state=\(capability.state.rawValue) providers=\(providers) detail=\(capability.detail)"
            )
        }
        lines.append("recent_bench_result_count=\(recentBenchResults.count)")
        lines.append("recent_bench_results:")
        if recentBenchResults.isEmpty {
            lines.append("(none)")
        } else {
            for result in recentBenchResults.prefix(5) {
                lines.append(AIRuntimeStatus.recentBenchSummaryLine(result))
            }
        }
        return lines.joined(separator: "\n")
    }

    public func providerDoctorText(
        ttl: Double = AIRuntimeStatus.recommendedHeartbeatTTL,
        blockedCapabilities: [String] = []
    ) -> String {
        let diagnoses = providerDiagnoses(ttl: ttl)
        let capabilities = localCapabilityDiagnoses(ttl: ttl, blockedCapabilities: blockedCapabilities)
        let readyProviders = diagnoses.filter { $0.state == .ready }.map(\.provider)
        let downProviders = diagnoses.filter { $0.state == .down }

        var parts: [String] = []
        if !isAlive(ttl: ttl) {
            parts.append("本地运行时心跳已过期，当前没有任何 provider 被视为就绪。")
        } else if readyProviders.isEmpty {
            if downProviders.isEmpty {
                parts.append("当前没有可用的本地 provider。")
            } else {
                let downSummary = downProviders
                    .map { AIRuntimeStatus.doctorProviderClause($0) }
                    .joined(separator: "; ")
                parts.append("当前没有可用的本地 provider：\(downSummary)。")
            }
        } else if downProviders.isEmpty {
            parts.append("本地运行时已完全就绪：\(readyProviders.joined(separator: ", "))。")
        } else {
            let downSummary = downProviders
                .map { AIRuntimeStatus.doctorProviderClause($0) }
                .joined(separator: "; ")
            parts.append(
                "本地运行时部分就绪：\(readyProviders.joined(separator: ", ")) 已就绪；\(downSummary)。"
            )
        }

        for capability in capabilities {
            switch capability.capabilityKey {
            case "ai.generate.local":
                if capability.state != .available {
                    parts.append("文本生成当前不可用：\(capability.detail)。")
                }
            case "ai.embed.local":
                if capability.state == .available {
                    parts.append("向量能力当前可通过 \(capability.providerIDs.joined(separator: ", ")) 使用。")
                } else if capability.state == .blocked {
                    parts.append("向量能力被 \(capability.capabilityKey) 阻止。")
                }
            case "ai.audio.local":
                if capability.state == .blocked {
                    parts.append("本地音频能力被 \(capability.capabilityKey) 阻止。")
                } else if capability.state == .available {
                    parts.append("本地音频能力当前可通过 \(capability.providerIDs.joined(separator: ", ")) 使用。")
                } else {
                    parts.append("本地音频能力当前不可用：\(capability.detail)。")
                }
            case "ai.vision.local":
                if capability.state == .blocked {
                    parts.append("本地视觉能力被 \(capability.capabilityKey) 阻止。")
                }
            default:
                break
            }
        }

        if isAlive(ttl: ttl),
           let recentBench = monitorSnapshot?.recentBenchResults.first,
           let routeClause = AIRuntimeStatus.recentBenchDoctorClause(recentBench) {
            parts.append(routeClause)
        }

        return parts.joined(separator: " ")
    }

    public func runtimeMonitorOperatorSummary(ttl: Double = AIRuntimeStatus.recommendedHeartbeatTTL) -> String {
        let runtimeAlive = isAlive(ttl: ttl)
        guard let monitorSnapshot else {
            return """
            runtime_alive=\(runtimeAlive ? "1" : "0")
            monitor_snapshot=none
            """
        }

        var lines: [String] = []
        lines.append("runtime_alive=\(runtimeAlive ? "1" : "0")")
        if let schemaVersion, !schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("status_schema_version=\(schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        if !monitorSnapshot.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("monitor_schema_version=\(monitorSnapshot.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        lines.append("monitor_provider_count=\(monitorSnapshot.providers.count)")
        lines.append("monitor_active_task_count=\(monitorSnapshot.queue.activeTaskCount)")
        lines.append("monitor_queued_task_count=\(monitorSnapshot.queue.queuedTaskCount)")
        lines.append("monitor_loaded_instance_count=\(monitorSnapshot.loadedInstances.count)")
        lines.append("monitor_fallback_ready_provider_count=\(monitorSnapshot.fallbackCounters.fallbackReadyProviderCount)")
        lines.append("monitor_fallback_only_provider_count=\(monitorSnapshot.fallbackCounters.fallbackOnlyProviderCount)")
        lines.append("monitor_last_error_count=\(monitorSnapshot.lastErrors.count)")
        lines.append("monitor_recent_bench_result_count=\(monitorSnapshot.recentBenchResults.count)")
        lines.append("monitor_providers:")
        for provider in monitorSnapshot.providers {
            let realTasks = provider.realTaskKinds.isEmpty ? "(none)" : provider.realTaskKinds.joined(separator: ",")
            let fallbackTasks = provider.fallbackTaskKinds.isEmpty ? "(none)" : provider.fallbackTaskKinds.joined(separator: ",")
            let unavailableTasks = provider.unavailableTaskKinds.isEmpty ? "(none)" : provider.unavailableTaskKinds.joined(separator: ",")
            let memoryText: String
            if provider.memoryState == "unknown" {
                memoryText = "unknown"
            } else {
                memoryText = "active=\(provider.activeMemoryBytes) peak=\(provider.peakMemoryBytes)"
            }
            let runtimeSource = provider.runtimeSource.isEmpty ? "unknown" : provider.runtimeSource
            let runtimeState = provider.runtimeResolutionState.isEmpty ? "unknown" : provider.runtimeResolutionState
            let runtimeReason = provider.runtimeReasonCode.isEmpty ? "none" : provider.runtimeReasonCode
            lines.append(
                "provider=\(provider.provider) ok=\(provider.ok ? "1" : "0") reason=\(provider.reasonCode.isEmpty ? "none" : provider.reasonCode) runtime_source=\(runtimeSource) runtime_state=\(runtimeState) runtime_reason=\(runtimeReason) fallback=\(provider.fallbackUsed ? "1" : "0") real_tasks=\(realTasks) fallback_tasks=\(fallbackTasks) unavailable_tasks=\(unavailableTasks) active=\(provider.activeTaskCount) queued=\(provider.queuedTaskCount) loaded_instances=\(provider.loadedInstanceCount) lifecycle=\(provider.lifecycleMode.isEmpty ? "unknown" : provider.lifecycleMode) residency=\(provider.residencyScope.isEmpty ? "unknown" : provider.residencyScope) memory=\(memoryText)"
            )
        }
        lines.append("monitor_active_tasks:")
        if monitorSnapshot.activeTasks.isEmpty {
            lines.append("(none)")
        } else {
            for task in monitorSnapshot.activeTasks {
                lines.append(
                    "provider=\(task.provider) task_kind=\(task.taskKind) model_id=\(task.modelId.isEmpty ? "(none)" : task.modelId) request_id=\(task.requestId.isEmpty ? "(none)" : task.requestId) device_id=\(task.deviceId.isEmpty ? "(none)" : task.deviceId) instance_key=\(task.instanceKey.isEmpty ? "(none)" : task.instanceKey)"
                )
            }
        }
        lines.append("monitor_recent_bench_results:")
        if monitorSnapshot.recentBenchResults.isEmpty {
            lines.append("(none)")
        } else {
            for result in monitorSnapshot.recentBenchResults.prefix(5) {
                lines.append(AIRuntimeStatus.recentBenchSummaryLine(result))
            }
        }
        lines.append("monitor_last_errors:")
        if monitorSnapshot.lastErrors.isEmpty {
            lines.append("(none)")
        } else {
            for error in monitorSnapshot.lastErrors {
                lines.append(
                    "provider=\(error.provider) severity=\(error.severity.isEmpty ? "unknown" : error.severity) code=\(error.code.isEmpty ? "none" : error.code) message=\(error.message.isEmpty ? "(none)" : error.message)"
                )
            }
        }
        return lines.joined(separator: "\n")
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
            taskKinds: ["speech_to_text", "text_to_speech"],
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
        let runtimeSource = diagnosis.runtimeSource.isEmpty ? "unknown" : diagnosis.runtimeSource
        let runtimeState = diagnosis.runtimeResolutionState.isEmpty ? "unknown" : diagnosis.runtimeResolutionState
        let runtimeReason = diagnosis.runtimeReasonCode.isEmpty ? "none" : diagnosis.runtimeReasonCode
        let tasks = diagnosis.availableTaskKinds.isEmpty ? "(none)" : diagnosis.availableTaskKinds.joined(separator: ",")
        let models = diagnosis.loadedModels.isEmpty ? "(none)" : diagnosis.loadedModels.joined(separator: ",")
        let backend = diagnosis.deviceBackend.isEmpty ? "unknown" : diagnosis.deviceBackend
        let importError = diagnosis.importError.isEmpty ? "" : " import_error=\(diagnosis.importError)"
        let sourcePath = diagnosis.runtimeSourcePath.isEmpty ? "" : " runtime_source_path=\(diagnosis.runtimeSourcePath)"
        return "provider=\(diagnosis.provider) state=\(diagnosis.state.rawValue) reason=\(reason) runtime_version=\(runtimeVersion) runtime_source=\(runtimeSource) runtime_state=\(runtimeState) runtime_reason=\(runtimeReason) fallback=\(diagnosis.fallbackUsed ? "1" : "0") device_backend=\(backend) tasks=\(tasks) loaded_models=\(models) loaded_model_count=\(diagnosis.loadedModelCount)\(sourcePath)\(importError)\(managedServiceLineSuffix(diagnosis.managedServiceState))"
    }

    private static func doctorProviderClause(_ diagnosis: AIRuntimeProviderDiagnosis) -> String {
        let primaryReason: String
        if !diagnosis.runtimeReasonCode.isEmpty, diagnosis.runtimeReasonCode != "ready" {
            primaryReason = diagnosis.runtimeReasonCode
        } else if !diagnosis.reasonCode.isEmpty {
            primaryReason = diagnosis.reasonCode
        } else if !diagnosis.importError.isEmpty {
            primaryReason = "import_error"
        } else {
            primaryReason = ""
        }

        var details: [String] = []
        if !primaryReason.isEmpty {
            details.append(primaryReason)
        }
        if let managed = diagnosis.managedServiceState {
            if !managed.processState.isEmpty {
                details.append("managed_service=\(managed.processState)")
            }
            if managed.startAttemptCount > 0 {
                details.append("attempts=\(managed.startAttemptCount)")
            }
            if !managed.lastStartError.isEmpty {
                details.append("last_start_error=\(managed.lastStartError)")
            }
        }
        if details.isEmpty {
            return "\(diagnosis.provider) unavailable"
        }
        return "\(diagnosis.provider) unavailable (\(details.joined(separator: "; ")))"
    }

    private static func managedServiceLineSuffix(_ managedState: AIRuntimeManagedServiceState?) -> String {
        guard let managedState else { return "" }
        var fields: [String] = []
        if !managedState.processState.isEmpty {
            fields.append(" managed_process=\(managedState.processState)")
        }
        if managedState.pid > 0 {
            fields.append(" managed_pid=\(managedState.pid)")
        }
        if managedState.startAttemptCount > 0 {
            fields.append(" managed_attempts=\(managedState.startAttemptCount)")
        }
        if managedState.lastProbeHTTPStatus > 0 {
            fields.append(" managed_probe_http=\(managedState.lastProbeHTTPStatus)")
        }
        if !managedState.lastStartError.isEmpty {
            fields.append(" managed_start_error=\(managedState.lastStartError)")
        }
        return fields.joined()
    }

    private static func recentBenchSummaryLine(_ result: ModelBenchResult) -> String {
        let summary = result.routeTraceSummary
        let provider = result.providerID.isEmpty ? "unknown" : result.providerID
        let taskKind = recentBenchTaskKind(result)
        let modelID = result.modelId.isEmpty ? "(none)" : result.modelId
        let executionPath = recentBenchExecutionPath(result)
        let fallbackMode = recentBenchFallbackMode(result)
        let blockedReason = summary?.blockedReasonCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? summary?.blockedReasonCode.trimmingCharacters(in: .whitespacesAndNewlines) ?? "none"
            : "none"
        let selectionReason = summary?.selectionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? summary?.selectionReason.trimmingCharacters(in: .whitespacesAndNewlines) ?? "none"
            : "none"
        let requestMode = summary?.requestMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? summary?.requestMode.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            : "unknown"
        let imageCount = max(summary?.imageCount ?? 0, summary?.resolvedImageCount ?? 0)
        let imageFiles = summary?.imageFiles.isEmpty == false ? summary?.imageFiles.joined(separator: ",") ?? "none" : "none"
        return "provider=\(provider) task_kind=\(taskKind) model_id=\(modelID) execution_path=\(executionPath) fallback_mode=\(fallbackMode) request_mode=\(requestMode) selection_reason=\(selectionReason) image_count=\(imageCount) blocked_reason=\(blockedReason) image_files=\(imageFiles) result_ok=\(result.ok ? "1" : "0")"
    }

    private static func recentBenchDoctorClause(_ result: ModelBenchResult) -> String? {
        guard let summary = result.routeTraceSummary else { return nil }
        let provider = result.providerID.isEmpty ? "the provider" : result.providerID
        let taskKind = recentBenchTaskKind(result)
        let modelID = result.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let executionPath = recentBenchExecutionPath(result)
        let fallbackMode = recentBenchFallbackMode(result)
        let imageCount = max(summary.imageCount, summary.resolvedImageCount)

        if !summary.blockedReasonCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var clause = "Most recent bench route for \(provider) \(taskKind)"
            if !modelID.isEmpty {
                clause += " on \(modelID)"
            }
            clause += " was blocked by \(summary.blockedReasonCode)"
            if let blockedImageIndex = summary.blockedImageIndex {
                clause += " at image \(blockedImageIndex + 1)"
            }
            clause += "."
            return clause
        }

        var clause = "最近一次快速评审路由显示，\(provider) 执行了 \(taskKind)"
        if !modelID.isEmpty {
            clause += "，模型为 \(modelID)"
        }
        if executionPath != "unknown" {
            clause += "，执行路径为 \(executionPath)"
        }
        if imageCount > 0 {
            clause += "，并携带了 \(imageCount) 张图片"
        }
        if fallbackMode != "none" {
            clause += "，使用回退模式 \(fallbackMode)"
        }
        clause += "。"
        if !result.ok {
            let reason = result.reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
            clause += reason.isEmpty ? "这次快速评审没有通过。" : "这次快速评审最终以 \(reason) 结束。"
        }
        return clause
    }

    private static func recentBenchTaskKind(_ result: ModelBenchResult) -> String {
        let traceTaskKind = result.routeTraceSummary?.selectedTaskKind.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !traceTaskKind.isEmpty {
            return traceTaskKind
        }
        let taskKind = result.taskKind.trimmingCharacters(in: .whitespacesAndNewlines)
        return taskKind.isEmpty ? "unknown" : taskKind
    }

    private static func recentBenchExecutionPath(_ result: ModelBenchResult) -> String {
        let executionPath = result.routeTraceSummary?.executionPath.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return executionPath.isEmpty ? "unknown" : executionPath
    }

    private static func recentBenchFallbackMode(_ result: ModelBenchResult) -> String {
        let routeFallback = result.routeTraceSummary?.fallbackMode.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !routeFallback.isEmpty {
            return routeFallback
        }
        let benchFallback = result.fallbackMode.trimmingCharacters(in: .whitespacesAndNewlines)
        return benchFallback.isEmpty ? "none" : benchFallback
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
                runtimeSource: rawValue.runtimeSource,
                runtimeSourcePath: rawValue.runtimeSourcePath,
                runtimeResolutionState: rawValue.runtimeResolutionState,
                runtimeReasonCode: rawValue.runtimeReasonCode,
                fallbackUsed: rawValue.fallbackUsed,
                runtimeHint: rawValue.runtimeHint,
                runtimeMissingRequirements: rawValue.runtimeMissingRequirements,
                runtimeMissingOptionalRequirements: rawValue.runtimeMissingOptionalRequirements,
                availableTaskKinds: rawValue.availableTaskKinds,
                loadedModels: rawValue.loadedModels,
                deviceBackend: rawValue.deviceBackend,
                updatedAt: rawValue.updatedAt == 0 ? legacyUpdatedAt : rawValue.updatedAt,
                importError: rawValue.importError,
                activeMemoryBytes: rawValue.activeMemoryBytes,
                peakMemoryBytes: rawValue.peakMemoryBytes,
                loadedModelCount: rawValue.loadedModelCount,
                lifecycleMode: rawValue.lifecycleMode,
                supportedLifecycleActions: rawValue.supportedLifecycleActions,
                warmupTaskKinds: rawValue.warmupTaskKinds,
                residencyScope: rawValue.residencyScope,
                loadedInstances: rawValue.loadedInstances,
                packId: rawValue.packId,
                packEngine: rawValue.packEngine,
                packVersion: rawValue.packVersion,
                packInstalled: rawValue.packInstalled,
                packEnabled: rawValue.packEnabled,
                packState: rawValue.packState,
                packReasonCode: rawValue.packReasonCode,
                managedServiceState: rawValue.managedServiceState
            )
        }

        if out["mlx"] == nil {
            out["mlx"] = AIRuntimeProviderStatus(
                provider: "mlx",
                ok: legacyMlxOk,
                reasonCode: legacyMlxOk ? "legacy_ready" : "legacy_unavailable",
                runtimeVersion: legacyRuntimeVersion,
                runtimeSource: "",
                runtimeSourcePath: "",
                runtimeResolutionState: "",
                runtimeReasonCode: "",
                fallbackUsed: false,
                runtimeHint: "",
                runtimeMissingRequirements: [],
                runtimeMissingOptionalRequirements: [],
                availableTaskKinds: legacyMlxOk ? ["text_generate"] : [],
                loadedModels: [],
                deviceBackend: "mps",
                updatedAt: legacyUpdatedAt,
                importError: legacyImportError,
                activeMemoryBytes: legacyActiveMemoryBytes,
                peakMemoryBytes: legacyPeakMemoryBytes,
                loadedModelCount: legacyLoadedModelCount,
                lifecycleMode: AIRuntimeProviderHubControlMode.mlxLegacy.rawValue,
                supportedLifecycleActions: [],
                warmupTaskKinds: [],
                residencyScope: "runtime_process",
                loadedInstances: [],
                packId: "",
                packEngine: "",
                packVersion: "",
                packInstalled: false,
                packEnabled: false,
                packState: "",
                packReasonCode: ""
            )
        }

        return out
    }

    private static func normalizedProviderPacks(
        _ rawProviderPacks: [AIRuntimeProviderPackStatus],
        providers: [String: AIRuntimeProviderStatus]
    ) -> [AIRuntimeProviderPackStatus] {
        var out: [String: AIRuntimeProviderPackStatus] = [:]
        for pack in rawProviderPacks {
            guard !pack.providerId.isEmpty else { continue }
            out[pack.providerId] = AIRuntimeProviderPackStatus(
                schemaVersion: pack.schemaVersion,
                providerId: pack.providerId,
                engine: pack.engine,
                version: pack.version,
                supportedFormats: pack.supportedFormats,
                supportedDomains: pack.supportedDomains,
                runtimeRequirements: pack.runtimeRequirements,
                minHubVersion: pack.minHubVersion,
                installed: pack.installed,
                enabled: pack.enabled,
                packState: pack.packState,
                reasonCode: pack.reasonCode
            )
        }

        for key in providers.keys.sorted() where out[key] == nil {
            out[key] = AIRuntimeProviderPackStatus.synthesizedLegacy(
                providerId: key,
                providerStatus: providers[key]
            )
        }

        return out.keys.sorted().compactMap { out[$0] }
    }

    private static func backfilledProviders(
        _ providers: [String: AIRuntimeProviderStatus],
        providerPacks: [AIRuntimeProviderPackStatus]
    ) -> [String: AIRuntimeProviderStatus] {
        let packByProvider = Dictionary(uniqueKeysWithValues: providerPacks.map { ($0.providerId, $0) })
        var out: [String: AIRuntimeProviderStatus] = [:]
        for (key, value) in providers {
            guard let pack = packByProvider[key] else {
                out[key] = value
                continue
            }
            out[key] = AIRuntimeProviderStatus(
                provider: value.provider,
                ok: value.ok,
                reasonCode: value.reasonCode,
                runtimeVersion: value.runtimeVersion,
                runtimeSource: value.runtimeSource,
                runtimeSourcePath: value.runtimeSourcePath,
                runtimeResolutionState: value.runtimeResolutionState,
                runtimeReasonCode: value.runtimeReasonCode,
                fallbackUsed: value.fallbackUsed,
                runtimeHint: value.runtimeHint,
                runtimeMissingRequirements: value.runtimeMissingRequirements,
                runtimeMissingOptionalRequirements: value.runtimeMissingOptionalRequirements,
                availableTaskKinds: value.availableTaskKinds,
                loadedModels: value.loadedModels,
                deviceBackend: value.deviceBackend,
                updatedAt: value.updatedAt,
                importError: value.importError,
                activeMemoryBytes: value.activeMemoryBytes,
                peakMemoryBytes: value.peakMemoryBytes,
                loadedModelCount: value.loadedModelCount,
                lifecycleMode: value.lifecycleMode,
                supportedLifecycleActions: value.supportedLifecycleActions,
                warmupTaskKinds: value.warmupTaskKinds,
                residencyScope: value.residencyScope,
                loadedInstances: value.loadedInstances,
                packId: value.packId.isEmpty ? pack.providerId : value.packId,
                packEngine: value.packEngine.isEmpty ? pack.engine : value.packEngine,
                packVersion: value.packVersion.isEmpty ? pack.version : value.packVersion,
                packInstalled: value.packInstalled || pack.installed,
                packEnabled: value.packEnabled || pack.enabled,
                packState: value.packState.isEmpty ? pack.packState : value.packState,
                packReasonCode: value.packReasonCode.isEmpty ? pack.reasonCode : value.packReasonCode,
                managedServiceState: value.managedServiceState
            )
        }
        return out
    }
}

public struct AIRuntimeStatusResolvedSnapshot: Sendable, Equatable {
    public var status: AIRuntimeStatus
    public var url: URL

    public init(status: AIRuntimeStatus, url: URL) {
        self.status = status
        self.url = url.standardizedFileURL
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

    private static func candidateURLs() -> [URL] {
        var candidates: [URL] = []
        var seen: Set<String> = []

        func append(_ url: URL) {
            let standardized = url.standardizedFileURL
            let path = standardized.path
            guard seen.insert(path).inserted else { return }
            candidates.append(standardized)
        }

        // The current Hub instance must prefer the runtime snapshot in its own writable base
        // directory. Falling through to a fresher snapshot from an unrelated source-run root
        // makes readiness nondeterministic when multiple runtimes are alive on the same machine.
        append(url())
        for base in SharedPaths.hubDirectoryCandidates() {
            append(base.appendingPathComponent(fileName))
        }
        return candidates
    }

    public static func loadResolved() -> AIRuntimeStatusResolvedSnapshot? {
        let candidates = candidateURLs()
        var freshestFallback: AIRuntimeStatusResolvedSnapshot?

        for (index, candidate) in candidates.enumerated() {
            guard let data = try? Data(contentsOf: candidate) else { continue }
            guard let decoded = try? JSONDecoder().decode(AIRuntimeStatus.self, from: data) else { continue }

            let resolved = AIRuntimeStatusResolvedSnapshot(status: decoded, url: candidate)
            if index == 0 {
                return resolved
            }
            if freshestFallback == nil || decoded.updatedAt >= freshestFallback?.status.updatedAt ?? 0 {
                freshestFallback = resolved
            }
        }
        return freshestFallback
    }

    public static func load() -> AIRuntimeStatus? {
        loadResolved()?.status
    }
}
