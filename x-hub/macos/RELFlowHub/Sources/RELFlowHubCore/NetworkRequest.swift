import Foundation

public struct HubNetworkRequest: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var source: String?
    public var projectId: String?
    public var rootPath: String?
    public var displayName: String?
    public var reason: String?
    public var requestedSeconds: Int?
    public var createdAt: Double

    public init(
        id: String,
        source: String? = nil,
        projectId: String? = nil,
        rootPath: String? = nil,
        displayName: String? = nil,
        reason: String? = nil,
        requestedSeconds: Int? = nil,
        createdAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.source = source
        self.projectId = projectId
        self.rootPath = rootPath
        self.displayName = displayName
        self.reason = reason
        self.requestedSeconds = requestedSeconds
        self.createdAt = createdAt
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case source
        case projectId = "project_id"
        case rootPath = "root_path"
        case displayName = "display_name"
        case reason
        case requestedSeconds = "requested_seconds"
        case createdAt = "created_at"
    }
}

public struct HubNetworkRequestList: Codable, Sendable, Equatable {
    public var updatedAt: Double
    public var requests: [HubNetworkRequest]

    public init(updatedAt: Double, requests: [HubNetworkRequest]) {
        self.updatedAt = updatedAt
        self.requests = requests
    }

    public static func empty() -> HubNetworkRequestList {
        HubNetworkRequestList(updatedAt: Date().timeIntervalSince1970, requests: [])
    }
}

public enum HubNetworkRequestStorage {
    private static let fileName = "network_requests.json"

    public static func url() -> URL {
        SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    public static func load() -> HubNetworkRequestList {
        let u = url()
        guard let data = try? Data(contentsOf: u) else { return .empty() }
        return (try? JSONDecoder().decode(HubNetworkRequestList.self, from: data)) ?? .empty()
    }

    public static func save(_ list: HubNetworkRequestList) {
        var cur = list
        cur.updatedAt = Date().timeIntervalSince1970
        if let data = try? JSONEncoder().encode(cur) {
            try? data.write(to: url(), options: .atomic)
        }
    }

    public static func add(_ req: HubNetworkRequest) -> HubNetworkRequestList {
        var list = load()
        if let idx = list.requests.firstIndex(where: { $0.id == req.id }) {
            list.requests[idx] = req
        } else {
            list.requests.append(req)
        }
        save(list)
        return list
    }

    public static func remove(id: String) -> HubNetworkRequestList {
        var list = load()
        list.requests.removeAll { $0.id == id }
        save(list)
        return list
    }
}
