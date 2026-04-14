import Foundation

public struct LocalModelVisionLoadProfile: Codable, Equatable, Sendable {
    public var imageMaxDimension: Int?

    public init(imageMaxDimension: Int? = nil) {
        self.imageMaxDimension = LocalModelVisionLoadProfile.normalizedImageMaxDimension(imageMaxDimension)
    }

    enum CodingKeys: String, CodingKey {
        case imageMaxDimension
    }

    enum SnakeCodingKeys: String, CodingKey {
        case imageMaxDimension = "image_max_dimension"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        self.init(
            imageMaxDimension: (try? c.decodeIfPresent(Int.self, forKey: .imageMaxDimension))
                ?? (try? s.decodeIfPresent(Int.self, forKey: .imageMaxDimension))
        )
    }

    public var isEmpty: Bool {
        imageMaxDimension == nil
    }

    private static func normalizedImageMaxDimension(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return min(16_384, max(32, value))
    }
}

public struct LocalModelLoadProfile: Codable, Equatable, Sendable {
    public var contextLength: Int
    public var gpuOffloadRatio: Double?
    public var ropeFrequencyBase: Double?
    public var ropeFrequencyScale: Double?
    public var evalBatchSize: Int?
    public var ttl: Int?
    public var parallel: Int?
    public var identifier: String?
    public var vision: LocalModelVisionLoadProfile?

    public init(
        contextLength: Int = 8192,
        gpuOffloadRatio: Double? = nil,
        ropeFrequencyBase: Double? = nil,
        ropeFrequencyScale: Double? = nil,
        evalBatchSize: Int? = nil,
        ttl: Int? = nil,
        parallel: Int? = nil,
        identifier: String? = nil,
        vision: LocalModelVisionLoadProfile? = nil
    ) {
        self.contextLength = max(512, contextLength)
        self.gpuOffloadRatio = LocalModelLoadProfile.normalizedRatio(gpuOffloadRatio)
        self.ropeFrequencyBase = LocalModelLoadProfile.normalizedPositive(ropeFrequencyBase)
        self.ropeFrequencyScale = LocalModelLoadProfile.normalizedPositive(ropeFrequencyScale)
        self.evalBatchSize = LocalModelLoadProfile.normalizedBatchSize(evalBatchSize)
        self.ttl = LocalModelLoadProfile.normalizedPositiveInt(ttl)
        self.parallel = LocalModelLoadProfile.normalizedPositiveInt(parallel)
        self.identifier = LocalModelLoadProfile.normalizedIdentifier(identifier)
        self.vision = LocalModelLoadProfile.normalizedVision(vision)
    }

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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        let v = try decoder.container(keyedBy: FlatVisionCodingKeys.self)
        let rawContextLength = (try? c.decode(Int.self, forKey: .contextLength))
            ?? (try? s.decode(Int.self, forKey: .contextLength))
            ?? 8192
        let rawGpuOffloadRatio = (try? c.decodeIfPresent(Double.self, forKey: .gpuOffloadRatio))
            ?? (try? s.decodeIfPresent(Double.self, forKey: .gpuOffloadRatio))
        let rawRopeFrequencyBase = (try? c.decodeIfPresent(Double.self, forKey: .ropeFrequencyBase))
            ?? (try? s.decodeIfPresent(Double.self, forKey: .ropeFrequencyBase))
        let rawRopeFrequencyScale = (try? c.decodeIfPresent(Double.self, forKey: .ropeFrequencyScale))
            ?? (try? s.decodeIfPresent(Double.self, forKey: .ropeFrequencyScale))
        let rawEvalBatchSize = (try? c.decodeIfPresent(Int.self, forKey: .evalBatchSize))
            ?? (try? s.decodeIfPresent(Int.self, forKey: .evalBatchSize))
        let rawTTL = (try? c.decodeIfPresent(Int.self, forKey: .ttl))
            ?? (try? s.decodeIfPresent(Int.self, forKey: .ttl))
        let rawParallel = (try? c.decodeIfPresent(Int.self, forKey: .parallel))
            ?? (try? s.decodeIfPresent(Int.self, forKey: .parallel))
        let rawIdentifier = (try? c.decodeIfPresent(String.self, forKey: .identifier))
            ?? (try? s.decodeIfPresent(String.self, forKey: .identifier))
        let rawVision = (try? c.decodeIfPresent(LocalModelVisionLoadProfile.self, forKey: .vision))
            ?? (try? s.decodeIfPresent(LocalModelVisionLoadProfile.self, forKey: .vision))
            ?? {
                let flatImageMaxDimension = (try? v.decodeIfPresent(Int.self, forKey: .visionImageMaxDimension))
                    ?? (try? v.decodeIfPresent(Int.self, forKey: .visionImageMaxDimensionCamel))
                guard flatImageMaxDimension != nil else { return nil }
                return LocalModelVisionLoadProfile(imageMaxDimension: flatImageMaxDimension)
            }()
        self.init(
            contextLength: rawContextLength,
            gpuOffloadRatio: rawGpuOffloadRatio,
            ropeFrequencyBase: rawRopeFrequencyBase,
            ropeFrequencyScale: rawRopeFrequencyScale,
            evalBatchSize: rawEvalBatchSize,
            ttl: rawTTL,
            parallel: rawParallel,
            identifier: rawIdentifier,
            vision: rawVision
        )
    }

    public func normalized(maxContextLength: Int? = nil) -> LocalModelLoadProfile {
        let limit = max(0, maxContextLength ?? 0)
        let effectiveContextLength: Int
        if limit > 0 {
            effectiveContextLength = min(max(512, contextLength), limit)
        } else {
            effectiveContextLength = max(512, contextLength)
        }
        return LocalModelLoadProfile(
            contextLength: effectiveContextLength,
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

    public func merged(
        with overrideProfile: LocalModelLoadProfileOverride?,
        maxContextLength: Int? = nil
    ) -> LocalModelLoadProfile {
        guard let overrideProfile else {
            return normalized(maxContextLength: maxContextLength)
        }
        return overrideProfile
            .applied(to: self)
            .normalized(maxContextLength: maxContextLength)
    }

    private static func normalizedRatio(_ value: Double?) -> Double? {
        guard let value else { return nil }
        guard value.isFinite else { return nil }
        return min(1.0, max(0.0, value))
    }

    private static func normalizedPositive(_ value: Double?) -> Double? {
        guard let value else { return nil }
        guard value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func normalizedBatchSize(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
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

    private static func normalizedVision(_ value: LocalModelVisionLoadProfile?) -> LocalModelVisionLoadProfile? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

public struct LocalModelLoadProfileOverride: Codable, Equatable, Sendable {
    public var contextLength: Int?
    public var gpuOffloadRatio: Double?
    public var ropeFrequencyBase: Double?
    public var ropeFrequencyScale: Double?
    public var evalBatchSize: Int?
    public var ttl: Int?
    public var parallel: Int?
    public var identifier: String?
    public var vision: LocalModelVisionLoadProfile?

    public init(
        contextLength: Int? = nil,
        gpuOffloadRatio: Double? = nil,
        ropeFrequencyBase: Double? = nil,
        ropeFrequencyScale: Double? = nil,
        evalBatchSize: Int? = nil,
        ttl: Int? = nil,
        parallel: Int? = nil,
        identifier: String? = nil,
        vision: LocalModelVisionLoadProfile? = nil
    ) {
        self.contextLength = contextLength
        self.gpuOffloadRatio = gpuOffloadRatio
        self.ropeFrequencyBase = ropeFrequencyBase
        self.ropeFrequencyScale = ropeFrequencyScale
        self.evalBatchSize = evalBatchSize
        self.ttl = ttl
        self.parallel = parallel
        self.identifier = identifier
        self.vision = vision
    }

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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        let v = try decoder.container(keyedBy: FlatVisionCodingKeys.self)
        contextLength = (try? c.decodeIfPresent(Int.self, forKey: .contextLength))
            ?? (try? s.decodeIfPresent(Int.self, forKey: .contextLength))
        gpuOffloadRatio = (try? c.decodeIfPresent(Double.self, forKey: .gpuOffloadRatio))
            ?? (try? s.decodeIfPresent(Double.self, forKey: .gpuOffloadRatio))
        ropeFrequencyBase = (try? c.decodeIfPresent(Double.self, forKey: .ropeFrequencyBase))
            ?? (try? s.decodeIfPresent(Double.self, forKey: .ropeFrequencyBase))
        ropeFrequencyScale = (try? c.decodeIfPresent(Double.self, forKey: .ropeFrequencyScale))
            ?? (try? s.decodeIfPresent(Double.self, forKey: .ropeFrequencyScale))
        evalBatchSize = (try? c.decodeIfPresent(Int.self, forKey: .evalBatchSize))
            ?? (try? s.decodeIfPresent(Int.self, forKey: .evalBatchSize))
        ttl = (try? c.decodeIfPresent(Int.self, forKey: .ttl))
            ?? (try? s.decodeIfPresent(Int.self, forKey: .ttl))
        parallel = (try? c.decodeIfPresent(Int.self, forKey: .parallel))
            ?? (try? s.decodeIfPresent(Int.self, forKey: .parallel))
        identifier = (try? c.decodeIfPresent(String.self, forKey: .identifier))
            ?? (try? s.decodeIfPresent(String.self, forKey: .identifier))
        vision = (try? c.decodeIfPresent(LocalModelVisionLoadProfile.self, forKey: .vision))
            ?? (try? s.decodeIfPresent(LocalModelVisionLoadProfile.self, forKey: .vision))
            ?? {
                let flatImageMaxDimension = (try? v.decodeIfPresent(Int.self, forKey: .visionImageMaxDimension))
                    ?? (try? v.decodeIfPresent(Int.self, forKey: .visionImageMaxDimensionCamel))
                guard flatImageMaxDimension != nil else { return nil }
                return LocalModelVisionLoadProfile(imageMaxDimension: flatImageMaxDimension)
            }()
    }

    public var isEmpty: Bool {
        contextLength == nil
            && gpuOffloadRatio == nil
            && ropeFrequencyBase == nil
            && ropeFrequencyScale == nil
            && evalBatchSize == nil
            && ttl == nil
            && parallel == nil
            && (identifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && (vision?.isEmpty ?? true)
    }

    public func applied(to base: LocalModelLoadProfile) -> LocalModelLoadProfile {
        LocalModelLoadProfile(
            contextLength: contextLength ?? base.contextLength,
            gpuOffloadRatio: gpuOffloadRatio ?? base.gpuOffloadRatio,
            ropeFrequencyBase: ropeFrequencyBase ?? base.ropeFrequencyBase,
            ropeFrequencyScale: ropeFrequencyScale ?? base.ropeFrequencyScale,
            evalBatchSize: evalBatchSize ?? base.evalBatchSize,
            ttl: ttl ?? base.ttl,
            parallel: parallel ?? base.parallel,
            identifier: identifier ?? base.identifier,
            vision: vision ?? base.vision
        )
    }
}

public struct HubPairedTerminalLocalModelProfile: Codable, Equatable, Sendable, Identifiable {
    public var deviceId: String
    public var modelId: String
    public var overrideProfile: LocalModelLoadProfileOverride
    public var updatedAtMs: Int64
    public var updatedBy: String
    public var note: String

    public var id: String { "\(deviceId)::\(modelId)" }

    public init(
        deviceId: String,
        modelId: String,
        overrideProfile: LocalModelLoadProfileOverride,
        updatedAtMs: Int64 = 0,
        updatedBy: String = "",
        note: String = ""
    ) {
        self.deviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.overrideProfile = overrideProfile
        self.updatedAtMs = updatedAtMs
        self.updatedBy = updatedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case modelId = "model_id"
        case overrideProfile = "override_profile"
        case updatedAtMs = "updated_at_ms"
        case updatedBy = "updated_by"
        case note
    }
}

public struct HubPairedTerminalLocalModelProfilesSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var updatedAtMs: Int64
    public var profiles: [HubPairedTerminalLocalModelProfile]

    public init(
        schemaVersion: String = "hub.paired_terminal_local_model_profiles.v1",
        updatedAtMs: Int64 = 0,
        profiles: [HubPairedTerminalLocalModelProfile] = []
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAtMs = updatedAtMs
        self.profiles = profiles
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case profiles
    }

    public static func empty() -> HubPairedTerminalLocalModelProfilesSnapshot {
        HubPairedTerminalLocalModelProfilesSnapshot()
    }
}

public enum HubPairedTerminalLocalModelProfilesStorage {
    public static let fileName = "hub_paired_terminal_local_model_profiles.json"

    public static func url() -> URL {
        if let group = SharedPaths.appGroupDirectory() {
            return group.appendingPathComponent(fileName)
        }
        return SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    public static func load() -> HubPairedTerminalLocalModelProfilesSnapshot {
        let profileURL = url()
        guard let data = try? Data(contentsOf: profileURL),
              let snapshot = try? JSONDecoder().decode(HubPairedTerminalLocalModelProfilesSnapshot.self, from: data) else {
            return .empty()
        }
        return snapshot
    }

    public static func save(_ snapshot: HubPairedTerminalLocalModelProfilesSnapshot) {
        var current = snapshot
        if current.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            current.schemaVersion = "hub.paired_terminal_local_model_profiles.v1"
        }
        if current.updatedAtMs <= 0 {
            current.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(current),
              let string = String(data: data, encoding: .utf8),
              let output = (string + "\n").data(using: .utf8) else {
            return
        }

        let profileURL = url()
        try? FileManager.default.createDirectory(
            at: profileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? output.write(to: profileURL, options: .atomic)
    }

    public static func upsert(_ profile: HubPairedTerminalLocalModelProfile) {
        let deviceId = profile.deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelId = profile.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deviceId.isEmpty, !modelId.isEmpty else { return }

        var snapshot = load()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        let normalized = HubPairedTerminalLocalModelProfile(
            deviceId: deviceId,
            modelId: modelId,
            overrideProfile: profile.overrideProfile,
            updatedAtMs: profile.updatedAtMs > 0 ? profile.updatedAtMs : nowMs,
            updatedBy: profile.updatedBy,
            note: profile.note
        )

        var replaced = false
        for index in snapshot.profiles.indices {
            if snapshot.profiles[index].deviceId == deviceId && snapshot.profiles[index].modelId == modelId {
                snapshot.profiles[index] = normalized
                replaced = true
            }
        }
        if !replaced {
            snapshot.profiles.append(normalized)
        }
        snapshot.updatedAtMs = nowMs
        save(snapshot)
    }

    public static func remove(deviceId: String, modelId: String) {
        let normalizedDeviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDeviceId.isEmpty, !normalizedModelId.isEmpty else { return }

        var snapshot = load()
        let originalCount = snapshot.profiles.count
        snapshot.profiles.removeAll {
            $0.deviceId == normalizedDeviceId && $0.modelId == normalizedModelId
        }
        guard snapshot.profiles.count != originalCount else { return }

        snapshot.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        save(snapshot)
    }

    public static func removeAll(deviceId: String) {
        let normalizedDeviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDeviceId.isEmpty else { return }

        var snapshot = load()
        let originalCount = snapshot.profiles.count
        snapshot.profiles.removeAll { $0.deviceId == normalizedDeviceId }
        guard snapshot.profiles.count != originalCount else { return }

        snapshot.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        save(snapshot)
    }

    public static func profile(deviceId: String, modelId: String) -> HubPairedTerminalLocalModelProfile? {
        let normalizedDeviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDeviceId.isEmpty, !normalizedModelId.isEmpty else { return nil }
        return load().profiles.first {
            $0.deviceId == normalizedDeviceId && $0.modelId == normalizedModelId
        }
    }
}
