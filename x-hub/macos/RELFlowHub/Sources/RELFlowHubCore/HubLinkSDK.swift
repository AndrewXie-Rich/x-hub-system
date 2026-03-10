import Foundation
import Darwin

public struct HubLinkConfig: Sendable, Equatable {
    public var appName: String
    public var bundleId: String
    public var appVersion: String
    public var clientId: String

    public init(appName: String, bundleId: String, appVersion: String, clientId: String) {
        self.appName = appName
        self.bundleId = bundleId
        self.appVersion = appVersion
        self.clientId = clientId
    }

    public static func fromBundle(clientIdKey: String = "hublink_client_id") -> HubLinkConfig {
        let bid = Bundle.main.bundleIdentifier ?? "unknown.app"
        let name = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? bid
        let ver = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        let defaults = UserDefaults.standard
        let existing = defaults.string(forKey: clientIdKey)
        let cid = (existing?.isEmpty == false) ? existing! : UUID().uuidString
        if existing == nil || existing?.isEmpty == true {
            defaults.set(cid, forKey: clientIdKey)
        }
        return HubLinkConfig(appName: name, bundleId: bid, appVersion: ver, clientId: cid)
    }
}

public struct HubLinkProject: Sendable, Equatable {
    public var projectId: String
    public var rootPath: String?
    public var displayName: String?

    public init(projectId: String, rootPath: String? = nil, displayName: String? = nil) {
        self.projectId = projectId
        self.rootPath = rootPath
        self.displayName = displayName
    }
}

public enum HubLinkScope: String, Sendable {
    case aiGenerate = "ai_generate"
    case projectSync = "project_sync"
    case needNetwork = "need_network"
    case webFetch = "web_fetch"
    case pushNotification = "push_notification"
}

public enum HubLinkError: Error, Sendable {
    case notConnected
    case hubUnavailable
    case badResponse
    case timeout
    case writeFailed
}

public enum HubLinkIPCMode: String, Sendable {
    case socket
    case file
}

public struct HubLinkStatus: Decodable, Sendable, Equatable {
    public var updatedAt: Double
    public var ipcMode: String?
    public var ipcPath: String?
    public var baseDir: String?
    public var appVersion: String?
    public var appBuild: String?

    public enum CodingKeys: String, CodingKey {
        case updatedAt = "updatedAt"
        case updated_at = "updated_at"
        case ipcMode = "ipcMode"
        case ipc_mode = "ipc_mode"
        case ipcPath = "ipcPath"
        case ipc_path = "ipc_path"
        case baseDir = "baseDir"
        case base_dir = "base_dir"
        case appVersion = "appVersion"
        case app_version = "app_version"
        case appBuild = "appBuild"
        case app_build = "app_build"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try? c.decode(Double.self, forKey: .updatedAt) {
            self.updatedAt = v
        } else if let v = try? c.decode(Double.self, forKey: .updated_at) {
            self.updatedAt = v
        } else {
            self.updatedAt = 0
        }
        self.ipcMode = (try? c.decode(String.self, forKey: .ipcMode)) ?? (try? c.decode(String.self, forKey: .ipc_mode))
        self.ipcPath = (try? c.decode(String.self, forKey: .ipcPath)) ?? (try? c.decode(String.self, forKey: .ipc_path))
        self.baseDir = (try? c.decode(String.self, forKey: .baseDir)) ?? (try? c.decode(String.self, forKey: .base_dir))
        self.appVersion = (try? c.decode(String.self, forKey: .appVersion)) ?? (try? c.decode(String.self, forKey: .app_version))
        self.appBuild = (try? c.decode(String.self, forKey: .appBuild)) ?? (try? c.decode(String.self, forKey: .app_build))
    }

    public func isAlive(ttl: Double) -> Bool {
        (Date().timeIntervalSince1970 - updatedAt) < ttl
    }
}

public final class HubLinkClient {
    public let config: HubLinkConfig
    public private(set) var status: HubLinkStatus?
    public private(set) var ipcMode: HubLinkIPCMode?
    public private(set) var ipcPath: URL?

    public init(config: HubLinkConfig) {
        self.config = config
    }

    @discardableResult
    public func connect(ttl: Double = 3.0) -> Bool {
        if let st = loadHubStatus(ttl: ttl) {
            status = st
            let mode = (st.ipcMode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if mode == "socket" {
                ipcMode = .socket
                if let p = st.ipcPath, !p.isEmpty {
                    ipcPath = URL(fileURLWithPath: p)
                } else {
                    ipcPath = URL(fileURLWithPath: SharedPaths.ipcSocketPath())
                }
            } else {
                ipcMode = .file
                if let p = st.ipcPath, !p.isEmpty {
                    ipcPath = URL(fileURLWithPath: p, isDirectory: true)
                } else if let base = st.baseDir, !base.isEmpty {
                    ipcPath = URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent("ipc_events", isDirectory: true)
                } else {
                    ipcPath = SharedPaths.ensurePublicHubDirectory().appendingPathComponent("ipc_events", isDirectory: true)
                }
            }
            return true
        }
        ipcMode = nil
        ipcPath = nil
        status = nil
        return false
    }

    @discardableResult
    public func register(scopes: [HubLinkScope]) -> Bool {
        // Best-effort: current Hub relies on heartbeat files for client presence.
        heartbeat(activity: .active, aiEnabled: false, modelMemoryBytes: nil, scopes: scopes, activeProjectId: nil)
        return status != nil
    }

    public func heartbeat(
        activity: HubClientActivity,
        aiEnabled: Bool,
        modelMemoryBytes: Int64?,
        scopes: [HubLinkScope] = [],
        activeProjectId: String? = nil
    ) {
        let now = Date().timeIntervalSince1970
        let appId = resolvedAppId()
        let payload = HubLinkHeartbeatPayload(
            appId: appId,
            appName: config.appName,
            activity: activity,
            aiEnabled: aiEnabled,
            modelMemoryBytes: modelMemoryBytes,
            updatedAt: now,
            bundleId: config.bundleId,
            clientId: config.clientId,
            appVersion: config.appVersion,
            scopes: scopes.map { $0.rawValue },
            activeProjectId: activeProjectId
        )
        let dir = ClientStorage.dir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("\(appId).json")
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: path, options: .atomic)
        }
    }

    public func projectSync(_ project: HubLinkProject, statusDigest: String? = nil, lastSummaryAt: Double? = nil, lastEventAt: Double? = nil) throws {
        guard let mode = ipcMode, let dir = ipcPath else { throw HubLinkError.notConnected }
        let now = Date().timeIntervalSince1970
        let display = (project.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let root = (project.rootPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = HubProjectSnapshot(
            projectId: project.projectId,
            rootPath: root,
            displayName: display.isEmpty ? project.projectId : display,
            statusDigest: statusDigest,
            lastSummaryAt: lastSummaryAt,
            lastEventAt: lastEventAt,
            updatedAt: now
        )
        let req = IPCRequest(type: "project_sync", reqId: UUID().uuidString, notification: nil, project: snapshot, network: nil)
        _ = try send(req, mode: mode, path: dir, expectResponse: (mode == .socket))
    }

    @discardableResult
    public func needNetwork(project: HubLinkProject, reason: String?, seconds: Int) throws -> Bool {
        guard let mode = ipcMode, let dir = ipcPath else { throw HubLinkError.notConnected }
        let now = Date().timeIntervalSince1970
        let display = (project.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let root = (project.rootPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let reqId = UUID().uuidString
        let payload = HubNetworkRequest(
            id: reqId,
            source: config.appName,
            projectId: project.projectId,
            rootPath: root.isEmpty ? nil : root,
            displayName: display.isEmpty ? project.projectId : display,
            reason: reason?.trimmingCharacters(in: .whitespacesAndNewlines),
            requestedSeconds: max(10, seconds),
            createdAt: now
        )
        let req = IPCRequest(type: "need_network", reqId: reqId, notification: nil, project: nil, network: payload)
        if let resp = try send(req, mode: mode, path: dir, expectResponse: (mode == .socket)) {
            return resp.ok
        }
        return true
    }

    public func pushNotification(title: String, body: String, dedupeKey: String? = nil, actionURL: String? = nil) throws {
        guard let mode = ipcMode, let dir = ipcPath else { throw HubLinkError.notConnected }
        let now = Date().timeIntervalSince1970
        let n = HubNotification(
            id: UUID().uuidString,
            source: config.appName,
            title: title,
            body: body,
            createdAt: now,
            dedupeKey: dedupeKey,
            actionURL: actionURL,
            snoozedUntil: nil,
            unread: true
        )
        let req = IPCRequest(type: "push_notification", reqId: UUID().uuidString, notification: n, project: nil, network: nil)
        _ = try send(req, mode: mode, path: dir, expectResponse: (mode == .socket))
    }

    public func disconnect() {
        // Best-effort: remove heartbeat so the satellite disappears.
        let appId = resolvedAppId()
        let path = ClientStorage.dir().appendingPathComponent("\(appId).json")
        try? FileManager.default.removeItem(at: path)
    }

    // MARK: - Internal

    private func resolvedAppId() -> String {
        let bid = config.bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cid = config.clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        if bid.isEmpty { return cid.isEmpty ? "unknown" : cid }
        if cid.isEmpty { return bid }
        return "\(bid):\(cid)"
    }

    private func loadHubStatus(ttl: Double) -> HubLinkStatus? {
        let env = (ProcessInfo.processInfo.environment["REL_FLOW_HUB_BASE_DIR"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !env.isEmpty {
            let u = URL(fileURLWithPath: NSString(string: env).expandingTildeInPath)
            if let st = readHubStatus(in: u), st.isAlive(ttl: ttl) {
                return st
            }
        }

        for cand in SharedPaths.hubDirectoryCandidates() {
            if let st = readHubStatus(in: cand), st.isAlive(ttl: ttl) {
                return st
            }
        }
        return nil
    }

    private func readHubStatus(in baseDir: URL) -> HubLinkStatus? {
        let url = baseDir.appendingPathComponent("hub_status.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HubLinkStatus.self, from: data)
    }

    private func send(_ req: IPCRequest, mode: HubLinkIPCMode, path: URL, expectResponse: Bool) throws -> IPCResponse? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(req) else { throw HubLinkError.writeFailed }

        switch mode {
        case .file:
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            let reqId = req.reqId ?? UUID().uuidString
            let file = path.appendingPathComponent("hublink_\(Int(Date().timeIntervalSince1970))_\(reqId).json")
            let tmp = path.appendingPathComponent(".hublink_\(reqId).tmp")
            try data.write(to: tmp, options: .atomic)
            try FileManager.default.moveItem(at: tmp, to: file)
            return nil
        case .socket:
            return try sendViaSocket(data: data, socketPath: path.path, expectResponse: expectResponse)
        }
    }

    private func sendViaSocket(data: Data, socketPath: String, expectResponse: Bool) throws -> IPCResponse? {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { throw HubLinkError.hubUnavailable }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        let bytes = Array(socketPath.utf8) + [0]
        if bytes.count > maxLen { throw HubLinkError.hubUnavailable }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: maxLen) { buf in
                for i in 0..<bytes.count {
                    buf[i] = bytes[i]
                }
            }
        }

        var a = addr
        let rc = withUnsafePointer(to: &a) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if rc != 0 { throw HubLinkError.hubUnavailable }

        var payload = data
        payload.append(0x0A)
        let written = payload.withUnsafeBytes { ptr in
            Darwin.write(fd, ptr.baseAddress, payload.count)
        }
        if written <= 0 { throw HubLinkError.writeFailed }

        guard expectResponse else { return nil }

        var tv = timeval(tv_sec: 1, tv_usec: 500_000)
        withUnsafePointer(to: &tv) { ptr in
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, ptr, socklen_t(MemoryLayout<timeval>.size))
        }

        var buffer = Data()
        var tmp = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = Darwin.read(fd, &tmp, tmp.count)
            if n <= 0 { break }
            buffer.append(contentsOf: tmp[0..<n])
            if buffer.contains(0x0A) { break }
        }
        guard let idx = buffer.firstIndex(of: 0x0A) else { throw HubLinkError.timeout }
        let line = buffer.prefix(upTo: idx)
        guard let resp = try? JSONDecoder().decode(IPCResponse.self, from: line) else {
            throw HubLinkError.badResponse
        }
        return resp
    }
}

private struct HubLinkHeartbeatPayload: Codable {
    var appId: String
    var appName: String
    var activity: HubClientActivity
    var aiEnabled: Bool
    var modelMemoryBytes: Int64?
    var updatedAt: Double

    // Extra metadata (Hub will ignore unknown keys).
    var bundleId: String
    var clientId: String
    var appVersion: String
    var scopes: [String]?
    var activeProjectId: String?

    enum CodingKeys: String, CodingKey {
        case appId = "app_id"
        case appName = "app_name"
        case activity
        case aiEnabled = "ai_enabled"
        case modelMemoryBytes = "model_memory_bytes"
        case updatedAt = "updated_at"
        case bundleId = "bundle_id"
        case clientId = "client_id"
        case appVersion = "app_version"
        case scopes
        case activeProjectId = "active_project_id"
    }
}
