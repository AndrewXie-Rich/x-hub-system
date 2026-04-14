import Foundation

public enum HubClientActivity: String, Codable, Sendable {
    case active
    case idle
}

public struct HubClientHeartbeat: Codable, Sendable, Equatable {
    public var appId: String
    public var appName: String
    public var activity: HubClientActivity
    public var aiEnabled: Bool
    public var modelMemoryBytes: Int64?
    public var updatedAt: Double

    public init(
        appId: String,
        appName: String,
        activity: HubClientActivity,
        aiEnabled: Bool,
        modelMemoryBytes: Int64? = nil,
        updatedAt: Double
    ) {
        self.appId = appId
        self.appName = appName
        self.activity = activity
        self.aiEnabled = aiEnabled
        self.modelMemoryBytes = modelMemoryBytes
        self.updatedAt = updatedAt
    }
}

public enum ClientStorage {
    public static func dir() -> URL {
        if let g = SharedPaths.appGroupDirectory() {
            return g.appendingPathComponent("clients", isDirectory: true)
        }
        return SharedPaths.ensureHubDirectory().appendingPathComponent("clients", isDirectory: true)
    }

    public static func readDirectoryCandidates() -> [URL] {
        var out: [URL] = []
        var seen: Set<String> = []

        func append(_ url: URL) {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { return }
            out.append(url)
        }

        if let group = SharedPaths.appGroupDirectory() {
            append(group.appendingPathComponent("clients", isDirectory: true))
        }

        for base in SharedPaths.hubDirectoryCandidates() {
            append(base.appendingPathComponent("clients", isDirectory: true))
        }

        return out
    }
}
