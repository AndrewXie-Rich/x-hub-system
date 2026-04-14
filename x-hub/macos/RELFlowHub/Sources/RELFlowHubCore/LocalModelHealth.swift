import Foundation

public extension Notification.Name {
    static let relflowhubLocalModelHealthChanged = Notification.Name("relflowhub.localModelHealthChanged")
}

public enum LocalModelHealthState: String, Codable, Equatable, Sendable {
    case healthy
    case degraded
    case blockedReadiness = "blocked_readiness"
    case blockedRuntime = "blocked_runtime"
    case unknownStale = "unknown_stale"
}

public enum LocalModelRecommendation: String, Codable, Equatable, Sendable {
    case recommended
    case neutral
    case discouraged
}

public struct LocalModelHealthRecord: Codable, Equatable, Identifiable, Sendable {
    public var modelId: String
    public var providerID: String
    public var state: LocalModelHealthState
    public var summary: String
    public var detail: String
    public var lastCheckedAt: TimeInterval
    public var lastSuccessAt: TimeInterval?

    public var id: String { modelId }

    public init(
        modelId: String,
        providerID: String,
        state: LocalModelHealthState,
        summary: String,
        detail: String,
        lastCheckedAt: TimeInterval,
        lastSuccessAt: TimeInterval? = nil
    ) {
        self.modelId = modelId
        self.providerID = providerID
        self.state = state
        self.summary = summary
        self.detail = detail
        self.lastCheckedAt = lastCheckedAt
        self.lastSuccessAt = lastSuccessAt
    }
}

public struct LocalModelHealthSnapshot: Codable, Equatable, Sendable {
    public var records: [LocalModelHealthRecord]
    public var updatedAt: TimeInterval

    public init(records: [LocalModelHealthRecord], updatedAt: TimeInterval) {
        self.records = records
        self.updatedAt = updatedAt
    }

    public static func empty() -> LocalModelHealthSnapshot {
        LocalModelHealthSnapshot(records: [], updatedAt: 0)
    }
}

public enum LocalModelHealthStorage {
    public static let fileName = "local_model_health.json"

    public static func url() -> URL {
        if let group = SharedPaths.appGroupDirectory() {
            return group.appendingPathComponent(fileName)
        }
        return SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    public static func load() -> LocalModelHealthSnapshot {
        guard let data = try? Data(contentsOf: url()),
              let snapshot = try? JSONDecoder().decode(LocalModelHealthSnapshot.self, from: data) else {
            return .empty()
        }
        return snapshot
    }

    public static func save(_ snapshot: LocalModelHealthSnapshot) {
        var current = snapshot
        current.updatedAt = Date().timeIntervalSince1970
        guard let data = try? JSONEncoder().encode(current) else { return }
        let destination = url()
        try? FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: destination, options: .atomic)
        NotificationCenter.default.post(name: .relflowhubLocalModelHealthChanged, object: nil)
    }

    public static func replace(records: [LocalModelHealthRecord]) {
        save(LocalModelHealthSnapshot(records: records, updatedAt: Date().timeIntervalSince1970))
    }
}

public enum LocalModelHealthSupport {
    public static let staleAfter: TimeInterval = 24 * 60 * 60

    public static func effectiveState(
        for health: LocalModelHealthRecord?,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> LocalModelHealthState? {
        guard let health else { return nil }
        guard health.lastCheckedAt > 0 else { return .unknownStale }
        if (now - health.lastCheckedAt) >= staleAfter {
            return .unknownStale
        }
        return health.state
    }

    public static func recommendation(
        for health: LocalModelHealthRecord?,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> LocalModelRecommendation {
        switch effectiveState(for: health, now: now) {
        case .healthy?:
            return .recommended
        case .blockedReadiness?, .blockedRuntime?:
            return .discouraged
        case .degraded?, .unknownStale?, nil:
            return .neutral
        }
    }

    public static func sortPriority(
        for health: LocalModelHealthRecord?,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Int {
        switch effectiveState(for: health, now: now) {
        case .healthy?:
            return 0
        case nil:
            return 1
        case .degraded?:
            return 2
        case .unknownStale?:
            return 3
        case .blockedReadiness?:
            return 4
        case .blockedRuntime?:
            return 5
        }
    }

    public static func recency(for health: LocalModelHealthRecord?) -> TimeInterval {
        max(health?.lastSuccessAt ?? 0, health?.lastCheckedAt ?? 0)
    }
}
