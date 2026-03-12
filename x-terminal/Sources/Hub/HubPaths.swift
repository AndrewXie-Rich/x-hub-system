import Foundation

enum HubPaths {
    private static let lock = DispatchQueue(label: "xterminal.hubpaths")
    private static var _baseDirOverride: URL? = nil
    private static var _baseDirOverridePinned: Bool = false
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

    static func baseDir() -> URL {
        if let o = baseDirOverride() {
            return o
        }
        let env = (ProcessInfo.processInfo.environment["REL_FLOW_HUB_BASE_DIR"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !env.isEmpty {
            return URL(fileURLWithPath: NSString(string: env).expandingTildeInPath)
        }
        if let live = liveBaseDirCandidate() {
            return live
        }
        for cand in candidateBaseDirs() where FileManager.default.fileExists(atPath: cand.path) {
            return cand
        }
        return defaultGroupBaseDir()
    }

    static func candidateBaseDirs() -> [URL] {
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
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Group Containers", isDirectory: true)
            .appendingPathComponent("group.rel.flowhub", isDirectory: true)
    }

    private static func liveBaseDirCandidate(ttl: Double = 5.0) -> URL? {
        for cand in candidateBaseDirs() {
            guard let status = readHubStatus(in: cand), status.isAlive(ttl: ttl) else { continue }
            let base = URL(fileURLWithPath: NSString(string: status.baseDir).expandingTildeInPath)
            return base
        }
        return nil
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
