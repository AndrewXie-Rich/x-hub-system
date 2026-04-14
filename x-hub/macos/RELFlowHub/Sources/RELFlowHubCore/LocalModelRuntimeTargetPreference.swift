import Foundation

public enum LocalModelRuntimeTargetPreferenceKind: String, Codable, Sendable {
    case pairedDevice = "paired_device"
    case loadedInstance = "loaded_instance"
}

public struct LocalModelRuntimeTargetPreference: Codable, Equatable, Sendable, Identifiable {
    public var modelId: String
    public var targetKind: String
    public var deviceId: String
    public var instanceKey: String
    public var updatedAtMs: Int64

    public var id: String { modelId }

    public init(
        modelId: String,
        targetKind: LocalModelRuntimeTargetPreferenceKind,
        deviceId: String = "",
        instanceKey: String = "",
        updatedAtMs: Int64 = 0
    ) {
        self.modelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.targetKind = targetKind.rawValue
        self.deviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.instanceKey = instanceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.updatedAtMs = max(0, updatedAtMs)
    }

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case targetKind = "target_kind"
        case deviceId = "device_id"
        case instanceKey = "instance_key"
        case updatedAtMs = "updated_at_ms"
    }

    public var kind: LocalModelRuntimeTargetPreferenceKind? {
        LocalModelRuntimeTargetPreferenceKind(rawValue: targetKind)
    }

    public var isValid: Bool {
        guard !modelId.isEmpty, let kind else { return false }
        switch kind {
        case .pairedDevice:
            return !deviceId.isEmpty
        case .loadedInstance:
            return !instanceKey.isEmpty
        }
    }
}

public struct LocalModelRuntimeTargetPreferencesSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var updatedAtMs: Int64
    public var preferences: [LocalModelRuntimeTargetPreference]

    public init(
        schemaVersion: String = "hub.local_model_target_preferences.v1",
        updatedAtMs: Int64 = 0,
        preferences: [LocalModelRuntimeTargetPreference] = []
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAtMs = updatedAtMs
        self.preferences = preferences
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case preferences
    }

    public static func empty() -> LocalModelRuntimeTargetPreferencesSnapshot {
        LocalModelRuntimeTargetPreferencesSnapshot()
    }
}

public enum LocalModelRuntimeTargetPreferencesStorage {
    public static let fileName = "hub_local_model_target_preferences.json"

    public static func url() -> URL {
        if let group = SharedPaths.appGroupDirectory() {
            return group.appendingPathComponent(fileName)
        }
        return SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    public static func load() -> LocalModelRuntimeTargetPreferencesSnapshot {
        var candidates: [URL] = []
        var seen: Set<String> = []

        func append(_ url: URL) {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { return }
            candidates.append(url)
        }

        if let group = SharedPaths.appGroupDirectory() {
            append(group.appendingPathComponent(fileName))
        }
        for base in SharedPaths.hubDirectoryCandidates() {
            append(base.appendingPathComponent(fileName))
        }

        var bestSnapshot: LocalModelRuntimeTargetPreferencesSnapshot?
        var bestUpdatedAtMs: Int64 = 0
        for candidate in candidates {
            guard let data = try? Data(contentsOf: candidate),
                  let snapshot = try? JSONDecoder().decode(LocalModelRuntimeTargetPreferencesSnapshot.self, from: data) else {
                continue
            }
            if bestSnapshot == nil || snapshot.updatedAtMs >= bestUpdatedAtMs {
                bestSnapshot = snapshot
                bestUpdatedAtMs = snapshot.updatedAtMs
            }
        }
        return bestSnapshot ?? .empty()
    }

    public static func save(_ snapshot: LocalModelRuntimeTargetPreferencesSnapshot) {
        var current = snapshot
        if current.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            current.schemaVersion = "hub.local_model_target_preferences.v1"
        }
        if current.updatedAtMs <= 0 {
            current.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        }
        current.preferences = current.preferences
            .filter(\.isValid)
            .sorted { lhs, rhs in
                if lhs.modelId == rhs.modelId {
                    return lhs.targetKind < rhs.targetKind
                }
                return lhs.modelId < rhs.modelId
            }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(current),
              let string = String(data: data, encoding: .utf8),
              let output = (string + "\n").data(using: .utf8) else {
            return
        }

        let targetURL = url()
        try? FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? output.write(to: targetURL, options: .atomic)
    }

    public static func upsert(_ preference: LocalModelRuntimeTargetPreference) {
        guard preference.isValid else { return }

        var snapshot = load()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        let normalized = LocalModelRuntimeTargetPreference(
            modelId: preference.modelId,
            targetKind: preference.kind ?? .pairedDevice,
            deviceId: preference.deviceId,
            instanceKey: preference.instanceKey,
            updatedAtMs: preference.updatedAtMs > 0 ? preference.updatedAtMs : nowMs
        )

        var replaced = false
        for index in snapshot.preferences.indices {
            if snapshot.preferences[index].modelId == normalized.modelId {
                snapshot.preferences[index] = normalized
                replaced = true
            }
        }
        if !replaced {
            snapshot.preferences.append(normalized)
        }
        snapshot.updatedAtMs = nowMs
        save(snapshot)
    }

    public static func remove(modelId: String) {
        let normalizedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModelId.isEmpty else { return }

        var snapshot = load()
        let originalCount = snapshot.preferences.count
        snapshot.preferences.removeAll { $0.modelId == normalizedModelId }
        guard snapshot.preferences.count != originalCount else { return }

        snapshot.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        save(snapshot)
    }

    public static func preference(modelId: String) -> LocalModelRuntimeTargetPreference? {
        let normalizedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModelId.isEmpty else { return nil }
        return load().preferences.first { $0.modelId == normalizedModelId }
    }
}
