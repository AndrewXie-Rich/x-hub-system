import Foundation

public enum HubNetworkPolicyMode: String, Codable, Sendable {
    case manual = "manual"
    case autoApprove = "auto_approve"
    case alwaysOn = "always_on"
    case deny = "deny"
}

public struct HubNetworkPolicyRule: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var appId: String
    public var projectId: String
    public var mode: HubNetworkPolicyMode
    public var maxSeconds: Int?
    public var createdAt: Double
    public var updatedAt: Double

    public init(
        id: String = UUID().uuidString,
        appId: String,
        projectId: String,
        mode: HubNetworkPolicyMode,
        maxSeconds: Int? = nil,
        createdAt: Double = Date().timeIntervalSince1970,
        updatedAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.appId = appId
        self.projectId = projectId
        self.mode = mode
        self.maxSeconds = maxSeconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case appId = "app_id"
        case projectId = "project_id"
        case mode
        case maxSeconds = "max_seconds"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct HubNetworkPolicyList: Codable, Sendable, Equatable {
    public var updatedAt: Double
    public var policies: [HubNetworkPolicyRule]

    public init(updatedAt: Double, policies: [HubNetworkPolicyRule]) {
        self.updatedAt = updatedAt
        self.policies = policies
    }

    public static func empty() -> HubNetworkPolicyList {
        HubNetworkPolicyList(updatedAt: Date().timeIntervalSince1970, policies: [])
    }
}

public enum HubNetworkPolicyStorage {
    private static let fileName = "network_policies.json"

    public static func url() -> URL {
        SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    public static func load() -> HubNetworkPolicyList {
        let u = url()
        guard let data = try? Data(contentsOf: u) else { return .empty() }
        return (try? JSONDecoder().decode(HubNetworkPolicyList.self, from: data)) ?? .empty()
    }

    public static func save(_ list: HubNetworkPolicyList) {
        var cur = list
        cur.updatedAt = Date().timeIntervalSince1970
        if let data = try? JSONEncoder().encode(cur) {
            try? data.write(to: url(), options: .atomic)
        }
    }

    @discardableResult
    public static func upsert(_ rule: HubNetworkPolicyRule) -> HubNetworkPolicyList {
        var list = load()
        if let idx = list.policies.firstIndex(where: { $0.id == rule.id }) {
            list.policies[idx] = rule
        } else {
            list.policies.append(rule)
        }
        save(list)
        return list
    }

    @discardableResult
    public static func upsert(appId: String, projectId: String, mode: HubNetworkPolicyMode, maxSeconds: Int?) -> HubNetworkPolicyList {
        let keyApp = appId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let keyProject = projectId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var list = load()
        if let idx = list.policies.firstIndex(where: { $0.appId.lowercased() == keyApp && $0.projectId.lowercased() == keyProject }) {
            var r = list.policies[idx]
            r.mode = mode
            r.maxSeconds = maxSeconds
            r.updatedAt = Date().timeIntervalSince1970
            list.policies[idx] = r
        } else {
            list.policies.append(
                HubNetworkPolicyRule(appId: appId, projectId: projectId, mode: mode, maxSeconds: maxSeconds)
            )
        }
        save(list)
        return list
    }

    @discardableResult
    public static func remove(id: String) -> HubNetworkPolicyList {
        var list = load()
        list.policies.removeAll { $0.id == id }
        save(list)
        return list
    }

    public static func match(appId: String, projectId: String) -> HubNetworkPolicyRule? {
        let a = appId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let p = projectId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let list = load().policies

        func score(_ r: HubNetworkPolicyRule) -> Int {
            let ra = r.appId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let rp = r.projectId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let appMatch = (ra == "*" || ra == a)
            let projMatch = (rp == "*" || rp == p)
            if !appMatch || !projMatch { return -1 }
            var s = 0
            if ra == a { s += 2 }
            if rp == p { s += 1 }
            return s
        }

        var best: HubNetworkPolicyRule?
        var bestScore = -1
        for r in list {
            let s = score(r)
            if s > bestScore {
                bestScore = s
                best = r
            }
        }
        return best
    }
}
