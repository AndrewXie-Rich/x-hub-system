import Foundation

enum HubPaths {
    private struct HubRuntimeStatusHeartbeat: Decodable {
        var updatedAt: Double?
        var pid: Int32?
    }

    struct LiveBaseDirResolution {
        var baseDir: URL
        var status: HubStatus?
    }

    private static let lock = DispatchQueue(label: "xterminal.hubpaths")
    private static var _baseDirOverride: URL? = nil
    private static var _baseDirOverridePinned: Bool = false
    private static var _candidateBaseDirsOverrideForTesting: [URL]? = nil
    private static var _defaultGroupBaseDirOverrideForTesting: URL? = nil
    private static let runtimeDirectoryAliases = ["XHub", "RELFlowHub"]

    static func setBaseDirOverride(_ url: URL?) {
        lock.sync {
            guard !_baseDirOverridePinned else { return }
            _baseDirOverride = url
        }
    }

    static func setPinnedBaseDirOverride(_ url: URL?) {
        lock.sync {
            _baseDirOverride = url
            _baseDirOverridePinned = (url != nil)
        }
    }

    static func clearPinnedBaseDirOverride() {
        lock.sync {
            _baseDirOverridePinned = false
            _baseDirOverride = nil
        }
    }

    static func baseDirOverride() -> URL? {
        lock.sync { _baseDirOverride }
    }

    static func setCandidateBaseDirsOverrideForTesting(_ urls: [URL]?) {
        lock.sync {
            _candidateBaseDirsOverrideForTesting = urls
        }
    }

    static func setDefaultGroupBaseDirOverrideForTesting(_ url: URL?) {
        lock.sync {
            _defaultGroupBaseDirOverrideForTesting = url
        }
    }

    static func baseDir() -> URL {
        if let o = baseDirOverride() {
            return o
        }
        let env = (ProcessInfo.processInfo.environment["REL_FLOW_HUB_BASE_DIR"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !env.isEmpty {
            return URL(fileURLWithPath: NSString(string: env).expandingTildeInPath)
        }
        if let live = liveBaseDirCandidate() {
            return live.baseDir
        }
        // When XT already has a remote pairing profile in ~/.axhub, local runtime
        // paths should not be inferred from arbitrary stale RELFlowHub/XHub folders.
        // In that mode the local base dir is only authoritative when a live hub
        // heartbeat exists; otherwise fall back to the canonical shared base dir.
        if hasRemotePairingState() {
            return defaultGroupBaseDir()
        }
        for cand in candidateBaseDirs() where FileManager.default.fileExists(atPath: cand.path) {
            return cand
        }
        return defaultGroupBaseDir()
    }

    static func candidateBaseDirs() -> [URL] {
        if let override = lock.sync(execute: { _candidateBaseDirsOverrideForTesting }) {
            return override
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let containerBase = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent("com.rel.flowhub", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
        let group = defaultGroupBaseDir()
        let tmpBase = URL(fileURLWithPath: "/private/tmp", isDirectory: true)

        var ordered: [URL] = [group]
        ordered.append(contentsOf: runtimeNamedDirs(in: containerBase))
        ordered.append(contentsOf: runtimeNamedDirs(in: tmpBase))
        ordered.append(contentsOf: runtimeNamedDirs(in: home))

        var seen: Set<String> = []
        return ordered.filter { seen.insert($0.path).inserted }
    }

    static func readHubStatus(in baseDir: URL) -> HubStatus? {
        let url = baseDir.appendingPathComponent("hub_status.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HubStatus.self, from: data)
    }

    private static func runtimeNamedDirs(in base: URL) -> [URL] {
        runtimeDirectoryAliases.map { base.appendingPathComponent($0, isDirectory: true) }
    }

    private static func defaultGroupBaseDir() -> URL {
        if let override = lock.sync(execute: { _defaultGroupBaseDirOverrideForTesting }) {
            return override
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Group Containers", isDirectory: true)
            .appendingPathComponent("group.rel.flowhub", isDirectory: true)
    }

    static func resolveLiveBaseDir(in candidate: URL, ttl: Double = 5.0) -> LiveBaseDirResolution? {
        if let status = readHubStatus(in: candidate), status.isAlive(ttl: ttl) {
            let base = URL(fileURLWithPath: NSString(string: status.baseDir).expandingTildeInPath)
            return LiveBaseDirResolution(
                baseDir: base,
                status: status
            )
        }

        guard runtimeHeartbeatIsFresh(in: candidate, ttl: max(12.0, ttl * 3.0)) else {
            return nil
        }

        let fallbackStatus = syntheticLiveHubStatus(
            in: candidate,
            baseDir: candidate
        )
        return LiveBaseDirResolution(
            baseDir: candidate,
            status: fallbackStatus
        )
    }

    private static func liveBaseDirCandidate(ttl: Double = 5.0) -> LiveBaseDirResolution? {
        for cand in candidateBaseDirs() {
            if let resolution = resolveLiveBaseDir(in: cand, ttl: ttl) {
                return resolution
            }
        }
        return nil
    }

    private static func runtimeHeartbeatIsFresh(in baseDir: URL, ttl: Double) -> Bool {
        let runtimeStatusURL = baseDir.appendingPathComponent("ai_runtime_status.json")
        let now = Date().timeIntervalSince1970

        if let data = try? Data(contentsOf: runtimeStatusURL),
           let heartbeat = try? JSONDecoder().decode(HubRuntimeStatusHeartbeat.self, from: data),
           let updatedAt = heartbeat.updatedAt,
           now - updatedAt < ttl {
            return true
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: runtimeStatusURL.path),
              let modifiedAt = attributes[.modificationDate] as? Date else {
            return false
        }
        return now - modifiedAt.timeIntervalSince1970 < ttl
    }

    private static func syntheticLiveHubStatus(
        in candidate: URL,
        baseDir: URL
    ) -> HubStatus {
        let existingStatus = readHubStatus(in: candidate)
        let runtimeStatusURL = baseDir.appendingPathComponent("ai_runtime_status.json")
        let modelsStateURL = baseDir.appendingPathComponent("models_state.json")
        let now = Date().timeIntervalSince1970

        var runtimeHeartbeat: HubRuntimeStatusHeartbeat?
        if let data = try? Data(contentsOf: runtimeStatusURL) {
            runtimeHeartbeat = try? JSONDecoder().decode(HubRuntimeStatusHeartbeat.self, from: data)
        }

        let runtimeModifiedAt = fileModificationDate(for: runtimeStatusURL)
        let modelsModifiedAt = fileModificationDate(for: modelsStateURL)

        return HubStatus(
            pid: runtimeHeartbeat?.pid ?? existingStatus?.pid,
            startedAt: existingStatus?.startedAt,
            updatedAt: max(now, runtimeModifiedAt.timeIntervalSince1970),
            ipcMode: existingStatus?.ipcMode ?? "file",
            ipcPath: existingStatus?.ipcPath ?? baseDir.appendingPathComponent("ipc_events", isDirectory: true).path,
            baseDir: baseDir.path,
            protocolVersion: existingStatus?.protocolVersion,
            aiReady: existingStatus?.aiReady ?? true,
            loadedModelCount: existingStatus?.loadedModelCount,
            modelsUpdatedAt: max(existingStatus?.modelsUpdatedAt ?? 0, modelsModifiedAt.timeIntervalSince1970)
        )
    }

    private static func fileModificationDate(for url: URL) -> Date {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modifiedAt = attributes[.modificationDate] as? Date else {
            return Date(timeIntervalSince1970: 0)
        }
        return modifiedAt
    }

    private static func hasRemotePairingState(fileManager: FileManager = .default) -> Bool {
        let stateDir = XTProcessPaths.defaultAxhubStateDir(fileManager: fileManager)
        let artifactNames = [
            "pairing.env",
            "connection.json",
            "hub.env",
        ]
        return artifactNames.contains { name in
            fileManager.fileExists(atPath: stateDir.appendingPathComponent(name).path)
        }
    }

    static func reqDir() -> URL {
        baseDir().appendingPathComponent("ai_requests", isDirectory: true)
    }

    static func respDir() -> URL {
        baseDir().appendingPathComponent("ai_responses", isDirectory: true)
    }

    static func cancelDir() -> URL {
        baseDir().appendingPathComponent("ai_cancels", isDirectory: true)
    }

    static func runtimeStatusURL() -> URL {
        baseDir().appendingPathComponent("ai_runtime_status.json")
    }

    static func modelsStateURL() -> URL {
        baseDir().appendingPathComponent("models_state.json")
    }
}
