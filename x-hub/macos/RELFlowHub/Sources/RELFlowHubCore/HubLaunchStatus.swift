import Foundation

public enum HubLaunchState: String, Codable, Sendable {
    case bootStart = "BOOT_START"
    case envValidate = "ENV_VALIDATE"
    case startGRPCServer = "START_GRPC_SERVER"
    case waitGRPCReady = "WAIT_GRPC_READY"
    case startBridge = "START_BRIDGE"
    case waitBridgeReady = "WAIT_BRIDGE_READY"
    case startRuntime = "START_RUNTIME"
    case waitRuntimeReady = "WAIT_RUNTIME_READY"
    case serving = "SERVING"
    case degradedServing = "DEGRADED_SERVING"
    case failed = "FAILED"
}

public enum HubLaunchComponent: String, Codable, Sendable {
    case env
    case db
    case grpc
    case bridge
    case runtime
}

public struct HubLaunchStep: Codable, Sendable, Equatable {
    public var state: HubLaunchState
    public var tsMs: Int64
    public var elapsedMs: Int64
    public var ok: Bool
    public var errorCode: String
    public var errorHint: String

    public init(
        state: HubLaunchState,
        tsMs: Int64,
        elapsedMs: Int64,
        ok: Bool,
        errorCode: String,
        errorHint: String
    ) {
        self.state = state
        self.tsMs = tsMs
        self.elapsedMs = elapsedMs
        self.ok = ok
        self.errorCode = errorCode
        self.errorHint = errorHint
    }

    enum CodingKeys: String, CodingKey {
        case state
        case tsMs = "ts_ms"
        case elapsedMs = "elapsed_ms"
        case ok
        case errorCode = "error_code"
        case errorHint = "error_hint"
    }
}

public struct HubLaunchRootCause: Codable, Sendable, Equatable {
    public var component: HubLaunchComponent
    public var errorCode: String
    public var detail: String

    public init(component: HubLaunchComponent, errorCode: String, detail: String = "") {
        self.component = component
        self.errorCode = errorCode
        self.detail = detail
    }

    enum CodingKeys: String, CodingKey {
        case component
        case errorCode = "error_code"
        case detail
    }
}

public struct HubLaunchDegraded: Codable, Sendable, Equatable {
    public var isDegraded: Bool
    public var blockedCapabilities: [String]

    public init(isDegraded: Bool, blockedCapabilities: [String]) {
        self.isDegraded = isDegraded
        self.blockedCapabilities = blockedCapabilities
    }

    enum CodingKeys: String, CodingKey {
        case isDegraded = "is_degraded"
        case blockedCapabilities = "blocked_capabilities"
    }
}

public struct HubLaunchStatusSnapshot: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var launchId: String
    public var updatedAtMs: Int64
    public var state: HubLaunchState
    public var steps: [HubLaunchStep]
    public var rootCause: HubLaunchRootCause?
    public var degraded: HubLaunchDegraded

    public init(
        schemaVersion: String = "hub_launch_status.v1",
        launchId: String = "",
        updatedAtMs: Int64,
        state: HubLaunchState,
        steps: [HubLaunchStep],
        rootCause: HubLaunchRootCause?,
        degraded: HubLaunchDegraded
    ) {
        self.schemaVersion = schemaVersion
        self.launchId = launchId
        self.updatedAtMs = updatedAtMs
        self.state = state
        self.steps = steps
        self.rootCause = rootCause
        self.degraded = degraded
    }

    public static func empty() -> HubLaunchStatusSnapshot {
        HubLaunchStatusSnapshot(
            updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000.0),
            state: .bootStart,
            steps: [],
            rootCause: nil,
            degraded: HubLaunchDegraded(isDegraded: false, blockedCapabilities: [])
        )
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case launchId = "launch_id"
        case updatedAtMs = "updated_at_ms"
        case state
        case steps
        case rootCause = "root_cause"
        case degraded
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decode(String.self, forKey: .schemaVersion)) ?? ""
        launchId = (try? c.decode(String.self, forKey: .launchId)) ?? ""
        updatedAtMs = (try? c.decode(Int64.self, forKey: .updatedAtMs)) ?? 0
        state = (try? c.decode(HubLaunchState.self, forKey: .state)) ?? .bootStart
        steps = (try? c.decode([HubLaunchStep].self, forKey: .steps)) ?? []
        rootCause = try? c.decode(HubLaunchRootCause.self, forKey: .rootCause)
        degraded = (try? c.decode(HubLaunchDegraded.self, forKey: .degraded)) ?? HubLaunchDegraded(isDegraded: false, blockedCapabilities: [])
    }
}

public struct HubLaunchHistorySnapshot: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var updatedAtMs: Int64
    public var maxEntries: Int
    public var launches: [HubLaunchStatusSnapshot]

    public init(
        schemaVersion: String = "hub_launch_history.v1",
        updatedAtMs: Int64,
        maxEntries: Int = 20,
        launches: [HubLaunchStatusSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAtMs = updatedAtMs
        self.maxEntries = maxEntries
        self.launches = launches
    }

    public static func empty(maxEntries: Int = 20) -> HubLaunchHistorySnapshot {
        HubLaunchHistorySnapshot(updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000.0), maxEntries: maxEntries, launches: [])
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case maxEntries = "max_entries"
        case launches
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decode(String.self, forKey: .schemaVersion)) ?? ""
        updatedAtMs = (try? c.decode(Int64.self, forKey: .updatedAtMs)) ?? 0
        maxEntries = max(1, (try? c.decode(Int.self, forKey: .maxEntries)) ?? 20)
        launches = (try? c.decode([HubLaunchStatusSnapshot].self, forKey: .launches)) ?? []
    }
}

public enum HubLaunchStatusStorage {
    public static let fileName = "hub_launch_status.json"

    private static func baseDirectory() -> URL {
        // Keep launch status co-located with hub_status.json so operators can find both
        // startup attribution and heartbeat in one place.
        let group = SharedPaths.appGroupDirectory()
        let container = SharedPaths.containerDataDirectory()?.appendingPathComponent("RELFlowHub", isDirectory: true)
        return group ?? container ?? SharedPaths.ensureHubDirectory()
    }

    private static func fallbackURL() -> URL {
        URL(fileURLWithPath: "/tmp/RELFlowHub", isDirectory: true).appendingPathComponent(fileName)
    }

    @discardableResult
    static func writeSnapshotData(_ data: Data, to u: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: u, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public static func url() -> URL {
        baseDirectory().appendingPathComponent(fileName)
    }

    public static func load() -> HubLaunchStatusSnapshot? {
        let decoder = JSONDecoder()
        let primary = url()
        if let data = try? Data(contentsOf: primary),
           let obj = try? decoder.decode(HubLaunchStatusSnapshot.self, from: data) {
            return obj
        }
        let fb = fallbackURL()
        if let data = try? Data(contentsOf: fb),
           let obj = try? decoder.decode(HubLaunchStatusSnapshot.self, from: data) {
            return obj
        }
        return nil
    }

    public static func save(_ snapshot: HubLaunchStatusSnapshot) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data0 = try? enc.encode(snapshot),
              let s = String(data: data0, encoding: .utf8),
              let out = (s + "\n").data(using: .utf8) else {
            return
        }

        let primary = url()
        if writeSnapshotData(out, to: primary) {
            return
        }
        _ = writeSnapshotData(out, to: fallbackURL())
    }
}

public enum HubLaunchHistoryStorage {
    public static let fileName = "hub_launch_history.json"

    private static func primaryURL() -> URL {
        // Co-locate next to hub_launch_status.json so operators can find everything in one place.
        HubLaunchStatusStorage.url().deletingLastPathComponent().appendingPathComponent(fileName)
    }

    private static func fallbackURL() -> URL {
        URL(fileURLWithPath: "/tmp/RELFlowHub", isDirectory: true).appendingPathComponent(fileName)
    }

    public static func url() -> URL {
        primaryURL()
    }

    public static func load(maxEntries: Int = 20) -> HubLaunchHistorySnapshot {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: primaryURL()),
           let obj = try? decoder.decode(HubLaunchHistorySnapshot.self, from: data) {
            return obj
        }
        if let data = try? Data(contentsOf: fallbackURL()),
           let obj = try? decoder.decode(HubLaunchHistorySnapshot.self, from: data) {
            return obj
        }
        return HubLaunchHistorySnapshot.empty(maxEntries: maxEntries)
    }

    public static func upsert(_ snapshot: HubLaunchStatusSnapshot, maxEntries: Int = 20) {
        let maxN = max(1, min(200, maxEntries))
        let rawId = snapshot.launchId.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacySeed = snapshot.steps.first?.tsMs ?? snapshot.updatedAtMs
        let id = rawId.isEmpty ? "legacy_\(legacySeed)" : rawId

        var hist = load(maxEntries: maxN)
        hist.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        hist.maxEntries = maxN

        // Replace existing entry for the same launch id, otherwise insert.
        var launches = hist.launches
        if let idx = launches.firstIndex(where: {
            if $0.launchId == id { return true }
            if !$0.launchId.isEmpty { return false }
            let seed = $0.steps.first?.tsMs ?? $0.updatedAtMs
            return "legacy_\(seed)" == id
        }) {
            var snap = snapshot
            if snap.launchId.isEmpty { snap.launchId = id }
            launches[idx] = snap
        } else {
            var snap = snapshot
            if snap.launchId.isEmpty { snap.launchId = id }
            launches.append(snap)
        }

        // Deduplicate + sort by recency.
        launches.sort { $0.updatedAtMs > $1.updatedAtMs }
        var seen: Set<String> = []
        launches = launches.compactMap { s in
            var out = s
            let sid0 = out.launchId.trimmingCharacters(in: .whitespacesAndNewlines)
            if sid0.isEmpty {
                let seed = out.steps.first?.tsMs ?? out.updatedAtMs
                out.launchId = "legacy_\(seed)"
            }
            let sid = out.launchId
            if seen.contains(sid) { return nil }
            seen.insert(sid)
            return out
        }

        if launches.count > maxN {
            launches = Array(launches.prefix(maxN))
        }
        hist.launches = launches

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data0 = try? enc.encode(hist),
              let s = String(data: data0, encoding: .utf8),
              let out = (s + "\n").data(using: .utf8) else {
            return
        }

        // Best-effort write (atomic); fall back to /tmp when needed.
        if HubLaunchStatusStorage.writeSnapshotData(out, to: primaryURL()) {
            return
        }
        _ = HubLaunchStatusStorage.writeSnapshotData(out, to: fallbackURL())
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: primaryURL())
        try? FileManager.default.removeItem(at: fallbackURL())
    }
}
