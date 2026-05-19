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

        // 2) Probe the last-known base dir plus normal candidates, then prefer the
        // candidate whose Hub model snapshot is freshest.
        let prev = UserDefaults.standard.string(forKey: defaultsKey) ?? UserDefaults.standard.string(forKey: legacyDefaultsKey)
        var candidates: [URL] = []
        if let prev, !prev.isEmpty {
            candidates.append(URL(fileURLWithPath: NSString(string: prev).expandingTildeInPath))
        }
        candidates.append(contentsOf: baseDirCandidates())
        if let live = bestLiveBaseDir(
            from: candidates,
            preferredBaseDir: candidates.first,
            ttl: ttl
        ) {
            persistResolvedBaseDir(live.baseDir)
            return (true, live.baseDir, live.status, nil)
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

    private struct LiveCandidate {
        var resolution: HubPaths.LiveBaseDirResolution
        var order: Int
        var preferred: Bool
        var modelsStateModifiedAt: TimeInterval
        var statusModelsUpdatedAt: TimeInterval
        var statusUpdatedAt: TimeInterval
    }

    private static func bestLiveBaseDir(
        from urls: [URL],
        preferredBaseDir: URL?,
        ttl: Double
    ) -> HubPaths.LiveBaseDirResolution? {
        var seen: Set<String> = []
        var best: LiveCandidate?
        let preferredPath = preferredBaseDir?.standardizedFileURL.path

        for (order, rawURL) in urls.enumerated() {
            let url = rawURL.standardizedFileURL
            guard seen.insert(url.path).inserted else { continue }
            guard let live = HubPaths.resolveLiveBaseDir(in: url, ttl: ttl) else { continue }

            let resolvedBase = live.baseDir.standardizedFileURL
            let candidate = LiveCandidate(
                resolution: HubPaths.LiveBaseDirResolution(
                    baseDir: resolvedBase,
                    status: live.status
                ),
                order: order,
                preferred: preferredPath == url.path || preferredPath == resolvedBase.path,
                modelsStateModifiedAt: fileModificationTime(
                    resolvedBase.appendingPathComponent("models_state.json")
                ),
                statusModelsUpdatedAt: live.status?.modelsUpdatedAt ?? 0,
                statusUpdatedAt: live.status?.updatedAt ?? 0
            )

            guard let currentBest = best else {
                best = candidate
                continue
            }
            if isBetterLiveCandidate(candidate, than: currentBest) {
                best = candidate
            }
        }

        return best?.resolution
    }

    private static func isBetterLiveCandidate(_ lhs: LiveCandidate, than rhs: LiveCandidate) -> Bool {
        if lhs.modelsStateModifiedAt != rhs.modelsStateModifiedAt {
            return lhs.modelsStateModifiedAt > rhs.modelsStateModifiedAt
        }
        if lhs.statusModelsUpdatedAt != rhs.statusModelsUpdatedAt {
            return lhs.statusModelsUpdatedAt > rhs.statusModelsUpdatedAt
        }
        if lhs.statusUpdatedAt != rhs.statusUpdatedAt {
            return lhs.statusUpdatedAt > rhs.statusUpdatedAt
        }
        if lhs.preferred != rhs.preferred {
            return lhs.preferred
        }
        return lhs.order < rhs.order
    }

    private static func fileModificationTime(_ url: URL) -> TimeInterval {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modifiedAt = attributes[.modificationDate] as? Date else {
            return 0
        }
        return modifiedAt.timeIntervalSince1970
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
