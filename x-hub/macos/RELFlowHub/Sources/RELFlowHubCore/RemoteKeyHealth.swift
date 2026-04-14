import Foundation

public extension Notification.Name {
    static let relflowhubRemoteKeyHealthChanged = Notification.Name("relflowhub.remoteKeyHealthChanged")
}

public enum RemoteKeyHealthState: String, Codable, Equatable, Sendable {
    case healthy
    case degraded
    case blockedQuota = "blocked_quota"
    case blockedAuth = "blocked_auth"
    case blockedNetwork = "blocked_network"
    case blockedProvider = "blocked_provider"
    case blockedConfig = "blocked_config"
    case unknownStale = "unknown_stale"
}

public enum RemoteKeyRecommendation: String, Codable, Equatable, Sendable {
    case recommended
    case neutral
    case discouraged
}

public struct RemoteKeyHealthRecord: Codable, Equatable, Identifiable, Sendable {
    public var keyReference: String
    public var backend: String
    public var providerHost: String?
    public var canaryModelID: String?
    public var state: RemoteKeyHealthState
    public var summary: String
    public var detail: String
    public var retryAtText: String?
    public var lastCheckedAt: TimeInterval
    public var lastSuccessAt: TimeInterval?

    public var id: String { keyReference }

    public init(
        keyReference: String,
        backend: String,
        providerHost: String? = nil,
        canaryModelID: String? = nil,
        state: RemoteKeyHealthState,
        summary: String,
        detail: String,
        retryAtText: String? = nil,
        lastCheckedAt: TimeInterval,
        lastSuccessAt: TimeInterval? = nil
    ) {
        self.keyReference = keyReference
        self.backend = backend
        self.providerHost = providerHost
        self.canaryModelID = canaryModelID
        self.state = state
        self.summary = summary
        self.detail = detail
        self.retryAtText = retryAtText
        self.lastCheckedAt = lastCheckedAt
        self.lastSuccessAt = lastSuccessAt
    }
}

public struct RemoteKeyHealthSnapshot: Codable, Equatable, Sendable {
    public var records: [RemoteKeyHealthRecord]
    public var updatedAt: TimeInterval

    public init(records: [RemoteKeyHealthRecord], updatedAt: TimeInterval) {
        self.records = records
        self.updatedAt = updatedAt
    }

    public static func empty() -> RemoteKeyHealthSnapshot {
        RemoteKeyHealthSnapshot(records: [], updatedAt: 0)
    }
}

public enum RemoteKeyHealthStorage {
    public static let fileName = "remote_key_health.json"

    public static func url() -> URL {
        if let group = SharedPaths.appGroupDirectory() {
            return group.appendingPathComponent(fileName)
        }
        return SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    public static func load() -> RemoteKeyHealthSnapshot {
        guard let data = try? Data(contentsOf: url()),
              let snapshot = try? JSONDecoder().decode(RemoteKeyHealthSnapshot.self, from: data) else {
            return .empty()
        }
        return snapshot
    }

    public static func save(_ snapshot: RemoteKeyHealthSnapshot) {
        var current = snapshot
        current.updatedAt = Date().timeIntervalSince1970
        guard let data = try? JSONEncoder().encode(current) else { return }
        let destination = url()
        try? FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: destination, options: .atomic)
        RemoteModelStorage.syncEnabledRemoteModelsIntoModelState()
        NotificationCenter.default.post(name: .relflowhubRemoteKeyHealthChanged, object: nil)
    }

    public static func replace(records: [RemoteKeyHealthRecord]) {
        save(RemoteKeyHealthSnapshot(records: records, updatedAt: Date().timeIntervalSince1970))
    }
}

public enum RemoteKeyHealthSupport {
    public static func recommendation(for health: RemoteKeyHealthRecord?) -> RemoteKeyRecommendation {
        switch health?.state {
        case .healthy?:
            return .recommended
        case .blockedQuota?, .blockedAuth?, .blockedNetwork?, .blockedProvider?, .blockedConfig?:
            return .discouraged
        case .degraded?, .unknownStale?, nil:
            return .neutral
        }
    }

    public static func sortPriority(for health: RemoteKeyHealthRecord?) -> Int {
        switch health?.state {
        case .healthy?:
            return 0
        case nil:
            return 1
        case .degraded?:
            return 2
        case .unknownStale?:
            return 3
        case .blockedQuota?:
            return 4
        case .blockedNetwork?:
            return 5
        case .blockedProvider?:
            return 6
        case .blockedAuth?:
            return 7
        case .blockedConfig?:
            return 8
        }
    }

    public static func recency(for health: RemoteKeyHealthRecord?) -> TimeInterval {
        max(health?.lastSuccessAt ?? 0, health?.lastCheckedAt ?? 0)
    }
}
