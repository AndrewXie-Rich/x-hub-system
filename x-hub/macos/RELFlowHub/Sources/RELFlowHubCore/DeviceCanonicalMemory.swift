import Foundation

public struct HubDeviceCanonicalMemoryItem: Codable, Sendable, Equatable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct HubDeviceCanonicalMemorySnapshot: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = "xt.device_canonical_memory_snapshot.v1"

    public var schemaVersion: String
    public var supervisorId: String
    public var displayName: String
    public var updatedAt: Double
    public var items: [HubDeviceCanonicalMemoryItem]

    public init(
        schemaVersion: String = HubDeviceCanonicalMemorySnapshot.currentSchemaVersion,
        supervisorId: String,
        displayName: String,
        updatedAt: Double,
        items: [HubDeviceCanonicalMemoryItem]
    ) {
        self.schemaVersion = schemaVersion
        self.supervisorId = supervisorId
        self.displayName = displayName
        self.updatedAt = updatedAt
        self.items = items
    }

    public enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case supervisorId = "supervisor_id"
        case displayName = "display_name"
        case updatedAt = "updated_at"
        case items
    }
}

public struct HubDeviceCanonicalMemoryStore: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = "xt.device_canonical_memory_store.v1"

    public var schemaVersion: String
    public var updatedAt: Double
    public var snapshots: [HubDeviceCanonicalMemorySnapshot]

    public init(
        schemaVersion: String = HubDeviceCanonicalMemoryStore.currentSchemaVersion,
        updatedAt: Double,
        snapshots: [HubDeviceCanonicalMemorySnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.snapshots = snapshots
    }

    public static func empty() -> HubDeviceCanonicalMemoryStore {
        HubDeviceCanonicalMemoryStore(updatedAt: Date().timeIntervalSince1970, snapshots: [])
    }

    public enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAt = "updated_at"
        case snapshots
    }
}

public enum HubDeviceCanonicalMemoryStorage {
    private static let fileName = "device_canonical_memory.json"

    public static func url(baseDir: URL? = nil) -> URL {
        let base = baseDir ?? SharedPaths.ensureHubDirectory()
        let dir = base.appendingPathComponent("memory", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    public static func load(baseDir: URL? = nil) -> HubDeviceCanonicalMemoryStore {
        let fileURL = url(baseDir: baseDir)
        guard let data = try? Data(contentsOf: fileURL) else { return .empty() }
        return (try? JSONDecoder().decode(HubDeviceCanonicalMemoryStore.self, from: data)) ?? .empty()
    }

    public static func save(_ store: HubDeviceCanonicalMemoryStore, baseDir: URL? = nil) {
        var current = store
        if current.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            current.schemaVersion = HubDeviceCanonicalMemoryStore.currentSchemaVersion
        }
        current.updatedAt = Date().timeIntervalSince1970
        guard let data = try? JSONEncoder().encode(current) else { return }
        try? data.write(to: url(baseDir: baseDir), options: .atomic)
    }

    @discardableResult
    public static func upsert(_ snapshot: HubDeviceCanonicalMemorySnapshot, baseDir: URL? = nil) -> HubDeviceCanonicalMemoryStore {
        var store = load(baseDir: baseDir)
        let normalized = normalizedSnapshot(snapshot)
        if let index = store.snapshots.firstIndex(where: { normalizedText($0.supervisorId) == normalized.supervisorId }) {
            store.snapshots[index] = normalized
        } else {
            store.snapshots.append(normalized)
        }
        save(store, baseDir: baseDir)
        return store
    }

    public static func lookup(
        supervisorId: String? = nil,
        displayName: String? = nil,
        baseDir: URL? = nil
    ) -> HubDeviceCanonicalMemorySnapshot? {
        let store = load(baseDir: baseDir)
        if store.snapshots.isEmpty { return nil }

        let normalizedSupervisorID = normalizedText(supervisorId)
        if !normalizedSupervisorID.isEmpty,
           let exact = store.snapshots.first(where: { normalizedText($0.supervisorId) == normalizedSupervisorID }) {
            return exact
        }

        let normalizedDisplay = normalizedText(displayName)
        if !normalizedDisplay.isEmpty,
           let exact = store.snapshots.first(where: {
               normalizedText($0.displayName).localizedCaseInsensitiveCompare(normalizedDisplay) == .orderedSame
           }) {
            return exact
        }

        if store.snapshots.count == 1 {
            return store.snapshots[0]
        }
        return nil
    }

    private static func normalizedSnapshot(_ snapshot: HubDeviceCanonicalMemorySnapshot) -> HubDeviceCanonicalMemorySnapshot {
        let supervisorId = normalizedText(snapshot.supervisorId)
        let displayName = normalizedText(snapshot.displayName)
        let items = snapshot.items.compactMap { raw -> HubDeviceCanonicalMemoryItem? in
            let key = normalizedText(raw.key)
            let value = normalizedText(raw.value)
            guard !key.isEmpty, !value.isEmpty else { return nil }
            return HubDeviceCanonicalMemoryItem(key: key, value: value)
        }

        return HubDeviceCanonicalMemorySnapshot(
            schemaVersion: HubDeviceCanonicalMemorySnapshot.currentSchemaVersion,
            supervisorId: supervisorId.isEmpty ? "supervisor-main" : supervisorId,
            displayName: displayName.isEmpty ? (supervisorId.isEmpty ? "Supervisor" : supervisorId) : displayName,
            updatedAt: max(0, snapshot.updatedAt),
            items: items
        )
    }

    private static func normalizedText(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
