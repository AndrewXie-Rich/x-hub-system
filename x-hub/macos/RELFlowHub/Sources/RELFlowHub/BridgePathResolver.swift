import Foundation
import RELFlowHubCore

enum BridgePathResolver {
    struct StatusSnapshot {
        var baseDir: URL
        var updatedAt: Double
        var enabledUntil: Double
        var alive: Bool
        var enabled: Bool
    }

    static func candidateBaseDirs() -> [URL] {
        var dirs: [URL] = []

        if let group = SharedPaths.appGroupDirectory() {
            dirs.append(group)
        }

        if let bridgeContainer = SharedPaths.containerDataDirectory(bundleId: "com.rel.flowhub.bridge") {
            dirs.append(bridgeContainer.appendingPathComponent("RELFlowHub", isDirectory: true))
        }

        if let hubContainer = SharedPaths.containerDataDirectory(bundleId: "com.rel.flowhub") {
            dirs.append(hubContainer.appendingPathComponent("RELFlowHub", isDirectory: true))
        }

        dirs.append(URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("RELFlowHub", isDirectory: true))
        dirs.append(SharedPaths.realHomeDirectory().appendingPathComponent("RELFlowHub", isDirectory: true))
        dirs.append(SharedPaths.sandboxHomeDirectory().appendingPathComponent("RELFlowHub", isDirectory: true))

        // Keep legacy fallback for older ad-hoc builds.
        dirs.append(SharedPaths.ensurePublicHubDirectory())

        var out: [URL] = []
        var seen: Set<String> = []
        for d in dirs {
            let p = d.path
            if seen.contains(p) { continue }
            seen.insert(p)
            out.append(d)
        }
        return out
    }

    static func readStatus(from baseDir: URL, ttl: Double = 3.5, now: Double = Date().timeIntervalSince1970) -> StatusSnapshot? {
        let statusFile = baseDir.appendingPathComponent("bridge_status.json")
        guard let data = try? Data(contentsOf: statusFile),
              let obj = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
            return nil
        }

        let updatedAt = max(doubleValue(obj["updatedAt"]), doubleValue(obj["updated_at"]))
        let enabledUntil = max(doubleValue(obj["enabledUntil"]), doubleValue(obj["enabled_until"]))
        let alive = updatedAt > 0 && (now - updatedAt) < max(0.5, ttl)
        let enabled = enabledUntil > now

        return StatusSnapshot(baseDir: baseDir, updatedAt: updatedAt, enabledUntil: enabledUntil, alive: alive, enabled: enabled)
    }

    static func bestStatus(ttl: Double = 3.5, now: Double = Date().timeIntervalSince1970) -> StatusSnapshot? {
        var best: StatusSnapshot?
        for dir in candidateBaseDirs() {
            guard let st = readStatus(from: dir, ttl: ttl, now: now) else { continue }
            if let cur = best {
                if isBetter(st, than: cur) {
                    best = st
                }
            } else {
                best = st
            }
        }
        return best
    }

    static func preferredBaseDirForWrites() -> URL {
        if let best = bestStatus(ttl: 120.0) {
            return best.baseDir
        }
        return candidateBaseDirs().first ?? SharedPaths.ensurePublicHubDirectory()
    }

    private static func isBetter(_ a: StatusSnapshot, than b: StatusSnapshot) -> Bool {
        if a.alive != b.alive { return a.alive }
        if a.enabled != b.enabled { return a.enabled }
        return a.updatedAt > b.updatedAt
    }

    private static func doubleValue(_ any: Any?) -> Double {
        if let v = any as? Double { return v }
        if let v = any as? Int { return Double(v) }
        if let v = any as? NSNumber { return v.doubleValue }
        if let s = any as? String, let v = Double(s) { return v }
        return 0
    }
}
