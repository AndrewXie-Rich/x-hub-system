import Foundation

public struct ModelBenchResult: Codable, Sendable, Equatable, Identifiable {
    public static let schemaVersion = "xhub.models_bench.v2"
    public static let legacyTextBenchKind = "legacy_text_bench"
    public static let quickBenchKind = "task_aware_quick_bench"

    public var resultID: String
    public var modelId: String
    public var providerID: String
    public var taskKind: String
    public var loadProfileHash: String
    public var fixtureProfile: String
    public var fixtureTitle: String
    public var measuredAt: Double
    public var runtimeVersion: String?
    public var schemaVersion: String?
    public var resultKind: String
    public var ok: Bool
    public var reasonCode: String
    public var runtimeSource: String
    public var runtimeSourcePath: String
    public var runtimeResolutionState: String
    public var runtimeReasonCode: String
    public var fallbackUsed: Bool
    public var runtimeHint: String
    public var runtimeMissingRequirements: [String]
    public var runtimeMissingOptionalRequirements: [String]
    public var verdict: String
    public var fallbackMode: String
    public var notes: [String]
    public var coldStartMs: Int?
    public var latencyMs: Int?
    public var peakMemoryBytes: Int64?
    public var throughputValue: Double?
    public var throughputUnit: String?
    public var effectiveContextLength: Int?
    public var loadConfig: LocalModelLoadProfile?
    public var promptTokens: Int?
    public var generationTokens: Int?
    public var promptTPS: Double?
    public var generationTPS: Double?
    public var routeTraceSummary: AIRuntimeRouteTraceSummary?

    public var id: String { resultID }
    public var loadConfigHash: String { loadProfileHash }
    public var currentContextLength: Int? { effectiveContextLength }

    public init(
        resultID: String = "",
        modelId: String,
        providerID: String = "",
        taskKind: String,
        loadProfileHash: String = "",
        fixtureProfile: String,
        fixtureTitle: String = "",
        measuredAt: Double = Date().timeIntervalSince1970,
        runtimeVersion: String? = nil,
        schemaVersion: String? = ModelBenchResult.schemaVersion,
        resultKind: String = ModelBenchResult.quickBenchKind,
        ok: Bool,
        reasonCode: String = "",
        runtimeSource: String = "",
        runtimeSourcePath: String = "",
        runtimeResolutionState: String = "",
        runtimeReasonCode: String = "",
        fallbackUsed: Bool = false,
        runtimeHint: String = "",
        runtimeMissingRequirements: [String] = [],
        runtimeMissingOptionalRequirements: [String] = [],
        verdict: String = "",
        fallbackMode: String = "",
        notes: [String] = [],
        coldStartMs: Int? = nil,
        latencyMs: Int? = nil,
        peakMemoryBytes: Int64? = nil,
        throughputValue: Double? = nil,
        throughputUnit: String? = nil,
        effectiveContextLength: Int? = nil,
        loadConfig: LocalModelLoadProfile? = nil,
        promptTokens: Int? = nil,
        generationTokens: Int? = nil,
        promptTPS: Double? = nil,
        generationTPS: Double? = nil,
        routeTraceSummary: AIRuntimeRouteTraceSummary? = nil
    ) {
        let normalizedModelID = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTaskKind = taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedFixtureProfile = fixtureProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLoadProfileHash = loadProfileHash.trimmingCharacters(in: .whitespacesAndNewlines)
        self.resultID = resultID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.compositeKey(
                modelId: normalizedModelID,
                taskKind: normalizedTaskKind,
                loadProfileHash: normalizedLoadProfileHash,
                fixtureProfile: normalizedFixtureProfile
            )
            : resultID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelId = normalizedModelID
        self.providerID = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.taskKind = normalizedTaskKind
        self.loadProfileHash = normalizedLoadProfileHash
        self.fixtureProfile = normalizedFixtureProfile
        self.fixtureTitle = fixtureTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.measuredAt = max(0, measuredAt)
        self.runtimeVersion = runtimeVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.schemaVersion = schemaVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.resultKind = resultKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.quickBenchKind
            : resultKind.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ok = ok
        self.reasonCode = reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.runtimeSource = runtimeSource.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.runtimeSourcePath = runtimeSourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.runtimeResolutionState = runtimeResolutionState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.runtimeReasonCode = runtimeReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fallbackUsed = fallbackUsed
        self.runtimeHint = runtimeHint.trimmingCharacters(in: .whitespacesAndNewlines)
        self.runtimeMissingRequirements = Self.normalizedNotes(runtimeMissingRequirements)
        self.runtimeMissingOptionalRequirements = Self.normalizedNotes(runtimeMissingOptionalRequirements)
        self.verdict = verdict.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fallbackMode = fallbackMode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = Self.normalizedNotes(notes)
        self.coldStartMs = Self.optionalNonNegative(coldStartMs)
        self.latencyMs = Self.optionalNonNegative(latencyMs)
        self.peakMemoryBytes = peakMemoryBytes.map { max(0, $0) }
        self.throughputValue = Self.optionalFinite(throughputValue)
        self.throughputUnit = throughputUnit?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.effectiveContextLength = Self.optionalNonNegative(effectiveContextLength)
        self.loadConfig = loadConfig?.normalized(maxContextLength: effectiveContextLength)
        self.promptTokens = Self.optionalNonNegative(promptTokens)
        self.generationTokens = Self.optionalNonNegative(generationTokens)
        self.promptTPS = Self.optionalFinite(promptTPS)
        self.generationTPS = Self.optionalFinite(generationTPS)
        self.routeTraceSummary = routeTraceSummary
    }

    public var isLegacyTextBench: Bool {
        resultKind == Self.legacyTextBenchKind
    }

    public static func compositeKey(
        modelId: String,
        taskKind: String,
        loadProfileHash: String,
        fixtureProfile: String
    ) -> String {
        [
            modelId.trimmingCharacters(in: .whitespacesAndNewlines),
            taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            loadProfileHash.trimmingCharacters(in: .whitespacesAndNewlines),
            fixtureProfile.trimmingCharacters(in: .whitespacesAndNewlines),
        ].joined(separator: "::")
    }

    private static func optionalNonNegative(_ value: Int?) -> Int? {
        guard let value else { return nil }
        return max(0, value)
    }

    private static func optionalFinite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func normalizedNotes(_ values: [String]) -> [String] {
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

    private static func legacyVerdict(generationTPS: Double) -> String {
        if generationTPS >= 30 {
            return "Fast"
        }
        if generationTPS >= 12 {
            return "Balanced"
        }
        return "Heavy"
    }

    enum CodingKeys: String, CodingKey {
        case resultID
        case modelId
        case providerID
        case provider
        case taskKind
        case loadProfileHash
        case loadConfigHash
        case fixtureProfile
        case fixtureTitle
        case measuredAt
        case runtimeVersion
        case schemaVersion
        case resultKind
        case ok
        case reasonCode
        case runtimeSource
        case runtimeSourcePath
        case runtimeResolutionState
        case runtimeReasonCode
        case fallbackUsed
        case runtimeHint
        case runtimeMissingRequirements
        case runtimeMissingOptionalRequirements
        case verdict
        case fallbackMode
        case notes
        case coldStartMs
        case latencyMs
        case peakMemoryBytes
        case throughputValue
        case throughputUnit
        case effectiveContextLength
        case currentContextLength
        case loadConfig
        case promptTokens
        case generationTokens
        case promptTPS
        case generationTPS
        case routeTraceSummary
    }

    enum SnakeCodingKeys: String, CodingKey {
        case resultID = "result_id"
        case modelId = "model_id"
        case providerID = "provider_id"
        case provider
        case taskKind = "task_kind"
        case loadProfileHash = "load_profile_hash"
        case loadConfigHash = "load_config_hash"
        case fixtureProfile = "fixture_profile"
        case fixtureTitle = "fixture_title"
        case measuredAt = "measured_at"
        case runtimeVersion = "runtime_version"
        case schemaVersion = "schema_version"
        case resultKind = "result_kind"
        case ok
        case reasonCode = "reason_code"
        case runtimeSource = "runtime_source"
        case runtimeSourcePath = "runtime_source_path"
        case runtimeResolutionState = "runtime_resolution_state"
        case runtimeReasonCode = "runtime_reason_code"
        case fallbackUsed = "fallback_used"
        case runtimeHint = "runtime_hint"
        case runtimeMissingRequirements = "runtime_missing_requirements"
        case runtimeMissingOptionalRequirements = "runtime_missing_optional_requirements"
        case verdict
        case fallbackMode = "fallback_mode"
        case notes
        case coldStartMs = "cold_start_ms"
        case latencyMs = "latency_ms"
        case peakMemoryBytes = "peak_memory_bytes"
        case throughputValue = "throughput_value"
        case throughputUnit = "throughput_unit"
        case effectiveContextLength = "effective_context_length"
        case currentContextLength = "current_context_length"
        case loadConfig = "load_config"
        case promptTokens = "prompt_tokens"
        case generationTokens = "generation_tokens"
        case promptTPS = "prompt_tps"
        case generationTPS = "generation_tps"
        case routeTraceSummary = "route_trace_summary"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        func decodeOptionalString(_ key: CodingKeys, _ snakeKey: SnakeCodingKeys) -> String? {
            (try? c.decodeIfPresent(String.self, forKey: key))
                ?? (try? s.decodeIfPresent(String.self, forKey: snakeKey))
        }
        func decodeOptionalInt(_ key: CodingKeys, _ snakeKey: SnakeCodingKeys) -> Int? {
            (try? c.decodeIfPresent(Int.self, forKey: key))
                ?? (try? s.decodeIfPresent(Int.self, forKey: snakeKey))
        }

        let legacyModelID = (try? c.decode(String.self, forKey: .modelId))
            ?? (try? s.decode(String.self, forKey: .modelId))
            ?? ""
        let legacyMeasuredAt = (try? c.decode(Double.self, forKey: .measuredAt))
            ?? (try? s.decode(Double.self, forKey: .measuredAt))
            ?? Date().timeIntervalSince1970
        let legacyPromptTokens = (try? c.decodeIfPresent(Int.self, forKey: .promptTokens))
            ?? (try? s.decodeIfPresent(Int.self, forKey: .promptTokens))
        let legacyGenerationTokens = (try? c.decodeIfPresent(Int.self, forKey: .generationTokens))
            ?? (try? s.decodeIfPresent(Int.self, forKey: .generationTokens))
        let legacyPromptTPS = (try? c.decodeIfPresent(Double.self, forKey: .promptTPS))
            ?? (try? s.decodeIfPresent(Double.self, forKey: .promptTPS))
        let legacyGenerationTPS = (try? c.decodeIfPresent(Double.self, forKey: .generationTPS))
            ?? (try? s.decodeIfPresent(Double.self, forKey: .generationTPS))
        let rawTaskKind = (try? c.decodeIfPresent(String.self, forKey: .taskKind))
            ?? (try? s.decodeIfPresent(String.self, forKey: .taskKind))
        let rawFixtureProfile = (try? c.decodeIfPresent(String.self, forKey: .fixtureProfile))
            ?? (try? s.decodeIfPresent(String.self, forKey: .fixtureProfile))

        let isLegacyShape = (rawTaskKind == nil || (rawTaskKind ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && (rawFixtureProfile == nil || (rawFixtureProfile ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && (legacyGenerationTPS != nil || legacyPromptTPS != nil)

        if isLegacyShape {
            let generationTPS = legacyGenerationTPS ?? 0
            let generationTokens = max(0, legacyGenerationTokens ?? 0)
            let latencyMs: Int?
            if generationTPS > 0, generationTokens > 0 {
                latencyMs = max(0, Int((Double(generationTokens) / generationTPS) * 1000.0))
            } else {
                latencyMs = nil
            }
            self.init(
                resultID: (try? c.decodeIfPresent(String.self, forKey: .resultID))
                    ?? (try? s.decodeIfPresent(String.self, forKey: .resultID))
                    ?? "",
                modelId: legacyModelID,
                providerID: "mlx",
                taskKind: "text_generate",
                loadProfileHash: "legacy_runtime",
                fixtureProfile: "legacy_mlx_text_default",
                fixtureTitle: "Legacy MLX text loop",
                measuredAt: legacyMeasuredAt,
                runtimeVersion: (try? c.decodeIfPresent(String.self, forKey: .runtimeVersion))
                    ?? (try? s.decodeIfPresent(String.self, forKey: .runtimeVersion)),
                schemaVersion: Self.schemaVersion,
                resultKind: Self.legacyTextBenchKind,
                ok: true,
                reasonCode: Self.legacyTextBenchKind,
                runtimeSource: "",
                runtimeSourcePath: "",
                runtimeResolutionState: "",
                runtimeReasonCode: "",
                fallbackUsed: false,
                runtimeHint: "",
                runtimeMissingRequirements: [],
                runtimeMissingOptionalRequirements: [],
                verdict: Self.legacyVerdict(generationTPS: generationTPS),
                fallbackMode: "",
                notes: ["legacy_text_bench"],
                coldStartMs: nil,
                latencyMs: latencyMs,
                peakMemoryBytes: (try? c.decodeIfPresent(Int64.self, forKey: .peakMemoryBytes))
                    ?? (try? s.decodeIfPresent(Int64.self, forKey: .peakMemoryBytes)),
                throughputValue: generationTPS > 0 ? generationTPS : nil,
                throughputUnit: "tokens_per_sec",
                effectiveContextLength: nil,
                loadConfig: nil,
                promptTokens: legacyPromptTokens,
                generationTokens: legacyGenerationTokens,
                promptTPS: legacyPromptTPS,
                generationTPS: legacyGenerationTPS,
                routeTraceSummary: nil
            )
            return
        }

        let decodedResultID = (try? c.decodeIfPresent(String.self, forKey: .resultID))
            ?? (try? s.decodeIfPresent(String.self, forKey: .resultID))
            ?? ""
        let decodedProviderID = decodeOptionalString(.providerID, .providerID)
            ?? decodeOptionalString(.provider, .provider)
            ?? ""
        let decodedLoadProfileHash = decodeOptionalString(.loadConfigHash, .loadConfigHash)
            ?? decodeOptionalString(.loadProfileHash, .loadProfileHash)
            ?? ""
        let decodedFixtureTitle = (try? c.decodeIfPresent(String.self, forKey: .fixtureTitle))
            ?? (try? s.decodeIfPresent(String.self, forKey: .fixtureTitle))
            ?? ""
        let decodedRuntimeVersion = (try? c.decodeIfPresent(String.self, forKey: .runtimeVersion))
            ?? (try? s.decodeIfPresent(String.self, forKey: .runtimeVersion))
        let decodedSchemaVersion = (try? c.decodeIfPresent(String.self, forKey: .schemaVersion))
            ?? (try? s.decodeIfPresent(String.self, forKey: .schemaVersion))
            ?? Self.schemaVersion
        let decodedResultKind = (try? c.decodeIfPresent(String.self, forKey: .resultKind))
            ?? (try? s.decodeIfPresent(String.self, forKey: .resultKind))
            ?? Self.quickBenchKind
        let decodedOK = (try? c.decodeIfPresent(Bool.self, forKey: .ok))
            ?? (try? s.decodeIfPresent(Bool.self, forKey: .ok))
            ?? false
        let decodedReasonCode = (try? c.decodeIfPresent(String.self, forKey: .reasonCode))
            ?? (try? s.decodeIfPresent(String.self, forKey: .reasonCode))
            ?? ""
        let decodedRuntimeSource = (try? c.decodeIfPresent(String.self, forKey: .runtimeSource))
            ?? (try? s.decodeIfPresent(String.self, forKey: .runtimeSource))
            ?? ""
        let decodedRuntimeSourcePath = (try? c.decodeIfPresent(String.self, forKey: .runtimeSourcePath))
            ?? (try? s.decodeIfPresent(String.self, forKey: .runtimeSourcePath))
            ?? ""
        let decodedRuntimeResolutionState = (try? c.decodeIfPresent(String.self, forKey: .runtimeResolutionState))
            ?? (try? s.decodeIfPresent(String.self, forKey: .runtimeResolutionState))
            ?? ""
        let decodedRuntimeReasonCode = (try? c.decodeIfPresent(String.self, forKey: .runtimeReasonCode))
            ?? (try? s.decodeIfPresent(String.self, forKey: .runtimeReasonCode))
            ?? ""
        let decodedFallbackUsed = (try? c.decodeIfPresent(Bool.self, forKey: .fallbackUsed))
            ?? (try? s.decodeIfPresent(Bool.self, forKey: .fallbackUsed))
            ?? false
        let decodedRuntimeHint = (try? c.decodeIfPresent(String.self, forKey: .runtimeHint))
            ?? (try? s.decodeIfPresent(String.self, forKey: .runtimeHint))
            ?? ""
        let decodedRuntimeMissingRequirements = (try? c.decodeIfPresent([String].self, forKey: .runtimeMissingRequirements))
            ?? (try? s.decodeIfPresent([String].self, forKey: .runtimeMissingRequirements))
            ?? []
        let decodedRuntimeMissingOptionalRequirements = (try? c.decodeIfPresent([String].self, forKey: .runtimeMissingOptionalRequirements))
            ?? (try? s.decodeIfPresent([String].self, forKey: .runtimeMissingOptionalRequirements))
            ?? []
        let decodedVerdict = (try? c.decodeIfPresent(String.self, forKey: .verdict))
            ?? (try? s.decodeIfPresent(String.self, forKey: .verdict))
            ?? ""
        let decodedFallbackMode = (try? c.decodeIfPresent(String.self, forKey: .fallbackMode))
            ?? (try? s.decodeIfPresent(String.self, forKey: .fallbackMode))
            ?? ""
        let decodedNotes = (try? c.decodeIfPresent([String].self, forKey: .notes))
            ?? (try? s.decodeIfPresent([String].self, forKey: .notes))
            ?? []
        let decodedColdStartMs = (try? c.decodeIfPresent(Int.self, forKey: .coldStartMs))
            ?? (try? s.decodeIfPresent(Int.self, forKey: .coldStartMs))
        let decodedLatencyMs = (try? c.decodeIfPresent(Int.self, forKey: .latencyMs))
            ?? (try? s.decodeIfPresent(Int.self, forKey: .latencyMs))
        let decodedPeakMemoryBytes = (try? c.decodeIfPresent(Int64.self, forKey: .peakMemoryBytes))
            ?? (try? s.decodeIfPresent(Int64.self, forKey: .peakMemoryBytes))
        let decodedThroughputValue = (try? c.decodeIfPresent(Double.self, forKey: .throughputValue))
            ?? (try? s.decodeIfPresent(Double.self, forKey: .throughputValue))
        let decodedThroughputUnit = (try? c.decodeIfPresent(String.self, forKey: .throughputUnit))
            ?? (try? s.decodeIfPresent(String.self, forKey: .throughputUnit))
        let decodedEffectiveContextLength = decodeOptionalInt(.currentContextLength, .currentContextLength)
            ?? decodeOptionalInt(.effectiveContextLength, .effectiveContextLength)
        let decodedLoadConfig = (try? c.decodeIfPresent(LocalModelLoadProfile.self, forKey: .loadConfig))
            ?? (try? s.decodeIfPresent(LocalModelLoadProfile.self, forKey: .loadConfig))
        let decodedRouteTraceSummary = (try? c.decodeIfPresent(AIRuntimeRouteTraceSummary.self, forKey: .routeTraceSummary))
            ?? (try? s.decodeIfPresent(AIRuntimeRouteTraceSummary.self, forKey: .routeTraceSummary))

        self.init(
            resultID: decodedResultID,
            modelId: legacyModelID,
            providerID: decodedProviderID,
            taskKind: rawTaskKind ?? "",
            loadProfileHash: decodedLoadProfileHash,
            fixtureProfile: rawFixtureProfile ?? "",
            fixtureTitle: decodedFixtureTitle,
            measuredAt: legacyMeasuredAt,
            runtimeVersion: decodedRuntimeVersion,
            schemaVersion: decodedSchemaVersion,
            resultKind: decodedResultKind,
            ok: decodedOK,
            reasonCode: decodedReasonCode,
            runtimeSource: decodedRuntimeSource,
            runtimeSourcePath: decodedRuntimeSourcePath,
            runtimeResolutionState: decodedRuntimeResolutionState,
            runtimeReasonCode: decodedRuntimeReasonCode,
            fallbackUsed: decodedFallbackUsed,
            runtimeHint: decodedRuntimeHint,
            runtimeMissingRequirements: decodedRuntimeMissingRequirements,
            runtimeMissingOptionalRequirements: decodedRuntimeMissingOptionalRequirements,
            verdict: decodedVerdict,
            fallbackMode: decodedFallbackMode,
            notes: decodedNotes,
            coldStartMs: decodedColdStartMs,
            latencyMs: decodedLatencyMs,
            peakMemoryBytes: decodedPeakMemoryBytes,
            throughputValue: decodedThroughputValue,
            throughputUnit: decodedThroughputUnit,
            effectiveContextLength: decodedEffectiveContextLength,
            loadConfig: decodedLoadConfig,
            promptTokens: legacyPromptTokens,
            generationTokens: legacyGenerationTokens,
            promptTPS: legacyPromptTPS,
            generationTPS: legacyGenerationTPS,
            routeTraceSummary: decodedRouteTraceSummary
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(resultID, forKey: .resultID)
        try c.encode(modelId, forKey: .modelId)
        try c.encode(providerID, forKey: .providerID)
        try c.encode(taskKind, forKey: .taskKind)
        try c.encode(loadProfileHash, forKey: .loadProfileHash)
        try c.encode(loadConfigHash, forKey: .loadConfigHash)
        try c.encode(fixtureProfile, forKey: .fixtureProfile)
        try c.encode(fixtureTitle, forKey: .fixtureTitle)
        try c.encode(measuredAt, forKey: .measuredAt)
        try c.encodeIfPresent(runtimeVersion, forKey: .runtimeVersion)
        try c.encodeIfPresent(schemaVersion, forKey: .schemaVersion)
        try c.encode(resultKind, forKey: .resultKind)
        try c.encode(ok, forKey: .ok)
        try c.encode(reasonCode, forKey: .reasonCode)
        try c.encode(runtimeSource, forKey: .runtimeSource)
        try c.encode(runtimeSourcePath, forKey: .runtimeSourcePath)
        try c.encode(runtimeResolutionState, forKey: .runtimeResolutionState)
        try c.encode(runtimeReasonCode, forKey: .runtimeReasonCode)
        try c.encode(fallbackUsed, forKey: .fallbackUsed)
        try c.encode(runtimeHint, forKey: .runtimeHint)
        try c.encode(runtimeMissingRequirements, forKey: .runtimeMissingRequirements)
        try c.encode(runtimeMissingOptionalRequirements, forKey: .runtimeMissingOptionalRequirements)
        try c.encode(verdict, forKey: .verdict)
        try c.encode(fallbackMode, forKey: .fallbackMode)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(coldStartMs, forKey: .coldStartMs)
        try c.encodeIfPresent(latencyMs, forKey: .latencyMs)
        try c.encodeIfPresent(peakMemoryBytes, forKey: .peakMemoryBytes)
        try c.encodeIfPresent(throughputValue, forKey: .throughputValue)
        try c.encodeIfPresent(throughputUnit, forKey: .throughputUnit)
        try c.encodeIfPresent(effectiveContextLength, forKey: .effectiveContextLength)
        try c.encodeIfPresent(currentContextLength, forKey: .currentContextLength)
        try c.encodeIfPresent(loadConfig, forKey: .loadConfig)
        try c.encodeIfPresent(promptTokens, forKey: .promptTokens)
        try c.encodeIfPresent(generationTokens, forKey: .generationTokens)
        try c.encodeIfPresent(promptTPS, forKey: .promptTPS)
        try c.encodeIfPresent(generationTPS, forKey: .generationTPS)
        try c.encodeIfPresent(routeTraceSummary, forKey: .routeTraceSummary)
    }
}

public struct ModelsBenchSnapshot: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var results: [ModelBenchResult]
    public var updatedAt: Double

    public init(
        schemaVersion: String = ModelBenchResult.schemaVersion,
        results: [ModelBenchResult],
        updatedAt: Double
    ) {
        self.schemaVersion = schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ModelBenchResult.schemaVersion
            : schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        self.results = Self.normalizedResults(results)
        self.updatedAt = max(0, updatedAt)
    }

    public static func empty() -> ModelsBenchSnapshot {
        ModelsBenchSnapshot(results: [], updatedAt: Date().timeIntervalSince1970)
    }

    private static func normalizedResults(_ values: [ModelBenchResult]) -> [ModelBenchResult] {
        var byID: [String: ModelBenchResult] = [:]
        for value in values {
            let key = value.id
            if let existing = byID[key], existing.measuredAt > value.measuredAt {
                continue
            }
            byID[key] = value
        }
        return byID.values.sorted {
            if $0.measuredAt == $1.measuredAt {
                return $0.id < $1.id
            }
            return $0.measuredAt > $1.measuredAt
        }
    }
}

public enum ModelBenchStorage {
    public static let fileName = "models_bench.json"

    public static func url() -> URL {
        if let g = SharedPaths.appGroupDirectory() {
            return g.appendingPathComponent(fileName)
        }
        return SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    public static func load() -> ModelsBenchSnapshot {
        let fileURL = url()
        guard let data = try? Data(contentsOf: fileURL) else {
            return .empty()
        }
        let decoder = JSONDecoder()
        if let snapshot = try? decoder.decode(ModelsBenchSnapshot.self, from: data) {
            return snapshot
        }
        if let arr = try? decoder.decode([ModelBenchResult].self, from: data) {
            return ModelsBenchSnapshot(results: arr, updatedAt: Date().timeIntervalSince1970)
        }
        if let legacy = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let models = legacy["models"] as? [String: Any] {
            var results: [ModelBenchResult] = []
            for (modelID, rawValue) in models {
                guard JSONSerialization.isValidJSONObject(rawValue),
                      let rowData = try? JSONSerialization.data(withJSONObject: rawValue),
                      var result = try? decoder.decode(ModelBenchResult.self, from: rowData) else {
                    continue
                }
                if result.modelId.isEmpty {
                    result.modelId = modelID
                    result.resultID = ModelBenchResult.compositeKey(
                        modelId: modelID,
                        taskKind: result.taskKind,
                        loadProfileHash: result.loadProfileHash,
                        fixtureProfile: result.fixtureProfile
                    )
                }
                results.append(result)
            }
            return ModelsBenchSnapshot(
                results: results,
                updatedAt: max(0, legacy["updatedAt"] as? Double ?? Date().timeIntervalSince1970)
            )
        }
        return .empty()
    }

    public static func save(_ snapshot: ModelsBenchSnapshot) {
        let fileURL = url()
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }

    @discardableResult
    public static func upsert(_ result: ModelBenchResult) -> ModelsBenchSnapshot {
        var snapshot = load()
        var retained = snapshot.results.filter { $0.id != result.id }
        retained.append(result)
        snapshot = ModelsBenchSnapshot(
            schemaVersion: ModelBenchResult.schemaVersion,
            results: retained,
            updatedAt: Date().timeIntervalSince1970
        )
        save(snapshot)
        return snapshot
    }
}
