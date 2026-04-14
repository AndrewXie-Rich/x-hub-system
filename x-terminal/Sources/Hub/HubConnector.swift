import Foundation
import Darwin

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
        guard (Date().timeIntervalSince1970 - updatedAt) < ttl else { return false }
        guard let pid, pid > 1 else { return true }
        if Darwin.kill(pid_t(pid), 0) == 0 { return true }
        return errno == EPERM
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
            if let live = HubPaths.resolveLiveBaseDir(in: u, ttl: ttl) {
                persistResolvedBaseDir(live.baseDir)
                return (true, live.baseDir, live.status, nil)
            }
        }

        // 2) Try last-known base dir (fast path).
        let prev = UserDefaults.standard.string(forKey: defaultsKey) ?? UserDefaults.standard.string(forKey: legacyDefaultsKey)
        if let prev, !prev.isEmpty {
            let u = URL(fileURLWithPath: NSString(string: prev).expandingTildeInPath)
            if let live = HubPaths.resolveLiveBaseDir(in: u, ttl: ttl) {
                persistResolvedBaseDir(live.baseDir)
                return (true, live.baseDir, live.status, nil)
            }
        }

        // 3) Scan candidates (supports both legacy RELFlowHub and new XHub runtime dirs).
        for cand in baseDirCandidates() {
            if let live = HubPaths.resolveLiveBaseDir(in: cand, ttl: ttl) {
                persistResolvedBaseDir(live.baseDir)
                return (true, live.baseDir, live.status, nil)
            }
        }

        // No live local runtime matched. Clear any unpinned override so the rest of XT
        // doesn't keep projecting an old RELFlowHub/XHub directory as authoritative.
        HubPaths.setBaseDirOverride(nil)
        if let prev, !prev.isEmpty {
            clearPersistedBaseDir()
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
            if let live = HubPaths.resolveLiveBaseDir(in: base, ttl: ttl) {
                return live.status
            }
        }

        // Otherwise, probe quickly.
        let res = connect(ttl: ttl)
        return res.status
    }

    private static func persistResolvedBaseDir(_ url: URL) {
        HubPaths.setBaseDirOverride(url)
        UserDefaults.standard.set(url.path, forKey: defaultsKey)
        UserDefaults.standard.set(url.path, forKey: legacyDefaultsKey)
    }

    private static func clearPersistedBaseDir() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: defaultsKey)
        defaults.removeObject(forKey: legacyDefaultsKey)
    }
}
