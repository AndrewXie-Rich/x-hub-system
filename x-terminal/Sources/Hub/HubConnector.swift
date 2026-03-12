import Foundation

struct HubStatus: Codable, Equatable {
    var pid: Int32?
    var startedAt: Double?
    var updatedAt: Double
    var ipcMode: String?
    var ipcPath: String?
    var baseDir: String
    var protocolVersion: Int?

    var aiReady: Bool?
    var loadedModelCount: Int?
    var modelsUpdatedAt: Double?

    func isAlive(ttl: Double = 3.0) -> Bool {
        (Date().timeIntervalSince1970 - updatedAt) < ttl
    }
}

enum HubConnector {
    private static let defaultsKey = "xterminal_hub_base_dir"
    private static let legacyDefaultsKey = "xterminal_hub_base_dir"

    static func connect(ttl: Double = 3.0) -> (ok: Bool, baseDir: URL?, status: HubStatus?, error: String?) {
        // 1) Try env override first.
        let env = (ProcessInfo.processInfo.environment["REL_FLOW_HUB_BASE_DIR"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !env.isEmpty {
            let u = URL(fileURLWithPath: NSString(string: env).expandingTildeInPath)
            if let st = HubPaths.readHubStatus(in: u), st.isAlive(ttl: ttl) {
                HubPaths.setBaseDirOverride(URL(fileURLWithPath: st.baseDir))
                UserDefaults.standard.set(st.baseDir, forKey: defaultsKey)
                UserDefaults.standard.set(st.baseDir, forKey: legacyDefaultsKey)
                return (true, URL(fileURLWithPath: st.baseDir), st, nil)
            }
        }

        // 2) Try last-known base dir (fast path).
        let prev = UserDefaults.standard.string(forKey: defaultsKey) ?? UserDefaults.standard.string(forKey: legacyDefaultsKey)
        if let prev, !prev.isEmpty {
            let u = URL(fileURLWithPath: NSString(string: prev).expandingTildeInPath)
            if let st = HubPaths.readHubStatus(in: u), st.isAlive(ttl: ttl) {
                HubPaths.setBaseDirOverride(URL(fileURLWithPath: st.baseDir))
                UserDefaults.standard.set(st.baseDir, forKey: defaultsKey)
                return (true, URL(fileURLWithPath: st.baseDir), st, nil)
            }
        }

        // 3) Scan candidates (supports both legacy RELFlowHub and new XHub runtime dirs).
        for cand in baseDirCandidates() {
            if let st = HubPaths.readHubStatus(in: cand), st.isAlive(ttl: ttl) {
                let base = URL(fileURLWithPath: st.baseDir)
                HubPaths.setBaseDirOverride(base)
                UserDefaults.standard.set(st.baseDir, forKey: defaultsKey)
                UserDefaults.standard.set(st.baseDir, forKey: legacyDefaultsKey)
                return (true, base, st, nil)
            }
        }

        return (false, nil, nil, "hub_not_running")
    }

    static func baseDirCandidates() -> [URL] {
        let fm = FileManager.default
        let ordered = HubPaths.candidateBaseDirs()
        var out: [URL] = []
        for u in ordered {
            if fm.fileExists(atPath: u.path) {
                out.append(u)
            }
        }
        // Also try non-existing dirs because Hub may create them after launch.
        for u in ordered where !out.contains(u) {
            out.append(u)
        }
        return out
    }

    static func readHubStatusIfAny(ttl: Double = 3.0) -> HubStatus? {
        // If connected override is set, read from it.
        if let base = HubPaths.baseDirOverride() {
            if let st = HubPaths.readHubStatus(in: base), st.isAlive(ttl: ttl) {
                return st
            }
        }

        // Otherwise, probe quickly.
        let res = connect(ttl: ttl)
        return res.status
    }
}
