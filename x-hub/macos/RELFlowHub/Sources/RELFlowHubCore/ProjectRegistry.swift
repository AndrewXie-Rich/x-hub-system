import Foundation

public struct HubProjectSnapshot: Codable, Sendable, Equatable {
    public var projectId: String
    public var rootPath: String
    public var displayName: String
    public var statusDigest: String?
    public var lastSummaryAt: Double?
    public var lastEventAt: Double?
    public var updatedAt: Double?

    public init(
        projectId: String,
        rootPath: String,
        displayName: String,
        statusDigest: String? = nil,
        lastSummaryAt: Double? = nil,
        lastEventAt: Double? = nil,
        updatedAt: Double? = nil
    ) {
        self.projectId = projectId
        self.rootPath = rootPath
        self.displayName = displayName
        self.statusDigest = statusDigest
        self.lastSummaryAt = lastSummaryAt
        self.lastEventAt = lastEventAt
        self.updatedAt = updatedAt
    }

    public enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case rootPath = "root_path"
        case displayName = "display_name"
        case statusDigest = "status_digest"
        case lastSummaryAt = "last_summary_at"
        case lastEventAt = "last_event_at"
        case updatedAt = "updated_at"
    }
}

public struct HubProjectRegistry: Codable, Sendable, Equatable {
    public static let currentVersion = "1.0"

    public var version: String
    public var updatedAt: Double
    public var projects: [HubProjectSnapshot]

    public init(version: String = HubProjectRegistry.currentVersion, updatedAt: Double, projects: [HubProjectSnapshot]) {
        self.version = version
        self.updatedAt = updatedAt
        self.projects = projects
    }

    public static func empty() -> HubProjectRegistry {
        HubProjectRegistry(updatedAt: Date().timeIntervalSince1970, projects: [])
    }
}

public enum HubProjectRegistryStorage {
    private static let fileName = "projects_registry.json"

    public static func url() -> URL {
        SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    public static func load() -> HubProjectRegistry {
        let u = url()
        guard let data = try? Data(contentsOf: u) else { return .empty() }
        return (try? JSONDecoder().decode(HubProjectRegistry.self, from: data)) ?? .empty()
    }

    public static func save(_ reg: HubProjectRegistry) {
        var cur = reg
        if cur.version.isEmpty { cur.version = HubProjectRegistry.currentVersion }
        cur.updatedAt = Date().timeIntervalSince1970
        if let data = try? JSONEncoder().encode(cur) {
            try? data.write(to: url(), options: .atomic)
        }
    }

    public static func upsert(_ project: HubProjectSnapshot) -> HubProjectRegistry {
        var reg = load()
        if let idx = reg.projects.firstIndex(where: { $0.projectId == project.projectId }) {
            reg.projects[idx] = project
        } else {
            reg.projects.append(project)
        }
        save(reg)
        return reg
    }
}
