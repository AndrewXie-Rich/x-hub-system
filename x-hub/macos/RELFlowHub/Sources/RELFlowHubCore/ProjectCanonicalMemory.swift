import Foundation

public struct HubProjectCanonicalMemoryItem: Codable, Sendable, Equatable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct HubProjectCanonicalMemorySnapshot: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = "xt.project_canonical_memory_snapshot.v1"

    public var schemaVersion: String
    public var projectId: String
    public var projectRoot: String
    public var displayName: String
    public var updatedAt: Double
    public var items: [HubProjectCanonicalMemoryItem]

    public init(
        schemaVersion: String = HubProjectCanonicalMemorySnapshot.currentSchemaVersion,
        projectId: String,
        projectRoot: String,
        displayName: String,
        updatedAt: Double,
        items: [HubProjectCanonicalMemoryItem]
    ) {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.projectRoot = projectRoot
        self.displayName = displayName
        self.updatedAt = updatedAt
        self.items = items
    }

    public enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case projectRoot = "project_root"
        case displayName = "display_name"
        case updatedAt = "updated_at"
        case items
    }
}

public struct HubProjectCanonicalMemoryStore: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = "xt.project_canonical_memory_store.v1"

    public var schemaVersion: String
    public var updatedAt: Double
    public var snapshots: [HubProjectCanonicalMemorySnapshot]

    public init(
        schemaVersion: String = HubProjectCanonicalMemoryStore.currentSchemaVersion,
        updatedAt: Double,
        snapshots: [HubProjectCanonicalMemorySnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.snapshots = snapshots
    }

    public static func empty() -> HubProjectCanonicalMemoryStore {
        HubProjectCanonicalMemoryStore(updatedAt: Date().timeIntervalSince1970, snapshots: [])
    }

    public enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAt = "updated_at"
        case snapshots
    }
}

public enum HubProjectCanonicalMemoryStorage {
    private static let fileName = "project_canonical_memory.json"

    public static func url(baseDir: URL? = nil) -> URL {
        let base = baseDir ?? SharedPaths.ensureHubDirectory()
        let dir = base.appendingPathComponent("memory", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    public static func load(baseDir: URL? = nil) -> HubProjectCanonicalMemoryStore {
        let fileURL = url(baseDir: baseDir)
        guard let data = try? Data(contentsOf: fileURL) else { return .empty() }
        return (try? JSONDecoder().decode(HubProjectCanonicalMemoryStore.self, from: data)) ?? .empty()
    }

    public static func save(_ store: HubProjectCanonicalMemoryStore, baseDir: URL? = nil) {
        var current = store
        if current.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            current.schemaVersion = HubProjectCanonicalMemoryStore.currentSchemaVersion
        }
        current.updatedAt = Date().timeIntervalSince1970
        guard let data = try? JSONEncoder().encode(current) else { return }
        try? data.write(to: url(baseDir: baseDir), options: .atomic)
    }

    @discardableResult
    public static func upsert(_ snapshot: HubProjectCanonicalMemorySnapshot, baseDir: URL? = nil) -> HubProjectCanonicalMemoryStore {
        var store = load(baseDir: baseDir)
        let normalized = normalizedSnapshot(snapshot)
        if let index = store.snapshots.firstIndex(where: { normalizedText($0.projectId) == normalized.projectId }) {
            store.snapshots[index] = normalized
        } else {
            store.snapshots.append(normalized)
        }
        save(store, baseDir: baseDir)
        return store
    }

    public static func lookup(
        projectId: String?,
        projectRoot: String?,
        displayName: String?,
        baseDir: URL? = nil
    ) -> HubProjectCanonicalMemorySnapshot? {
        let store = load(baseDir: baseDir)
        if store.snapshots.isEmpty { return nil }

        let normalizedProjectId = normalizedText(projectId)
        if !normalizedProjectId.isEmpty,
           let exact = store.snapshots.first(where: { normalizedText($0.projectId) == normalizedProjectId }) {
            return exact
        }

        let normalizedRoot = normalizedText(projectRoot)
        if !normalizedRoot.isEmpty,
           let exact = store.snapshots.first(where: { normalizedText($0.projectRoot) == normalizedRoot }) {
            return exact
        }

        let normalizedDisplay = normalizedText(displayName)
        if !normalizedDisplay.isEmpty,
           let exact = store.snapshots.first(where: {
               normalizedText($0.displayName).localizedCaseInsensitiveCompare(normalizedDisplay) == .orderedSame
           }) {
            return exact
        }

        return nil
    }

    private static func normalizedSnapshot(_ snapshot: HubProjectCanonicalMemorySnapshot) -> HubProjectCanonicalMemorySnapshot {
        let items = snapshot.items.compactMap { raw -> HubProjectCanonicalMemoryItem? in
            let key = normalizedText(raw.key)
            let value = normalizedText(raw.value)
            guard !key.isEmpty, !value.isEmpty else { return nil }
            return HubProjectCanonicalMemoryItem(key: key, value: value)
        }

        return HubProjectCanonicalMemorySnapshot(
            schemaVersion: HubProjectCanonicalMemorySnapshot.currentSchemaVersion,
            projectId: normalizedText(snapshot.projectId),
            projectRoot: normalizedText(snapshot.projectRoot),
            displayName: normalizedText(snapshot.displayName),
            updatedAt: max(0, snapshot.updatedAt),
            items: items
        )
    }

    private static func normalizedText(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
