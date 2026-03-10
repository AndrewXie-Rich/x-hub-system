import Foundation
import Darwin
import Security

public enum SharedPaths {
    // Dev builds are often ad-hoc signed (no TeamIdentifier). On recent macOS versions,
    // touching App Group containers from such builds can trigger repeated
    // “would like to access data from other apps” prompts. Cache team id once.
    private static let cachedTeamIdentifier: String? = { () -> String? in
        var code: SecCode?
        let selfErr = SecCodeCopySelf(SecCSFlags(), &code)
        guard selfErr == errSecSuccess, let code else { return nil }

        var staticCode: SecStaticCode?
        let staticErr = SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode)
        guard staticErr == errSecSuccess, let staticCode else { return nil }

        var info: CFDictionary?
        let infoErr = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard infoErr == errSecSuccess, let dict = info as? [String: Any] else { return nil }

        let key = kSecCodeInfoTeamIdentifier as String
        return dict[key] as? String
    }()
    // In App Sandbox, FileManager.homeDirectoryForCurrentUser points to the container.
    // For IPC with non-sandboxed tools, we need the real user home directory.
    public static func realHomeDirectory() -> URL {
        // getpwuid(getuid()) returns the user record home (e.g. /Users/<username>).
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        // Fallback: may still be container under sandbox, but better than crashing.
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static func sandboxHomeDirectory() -> URL {
        // Under App Sandbox this is typically: ~/Library/Containers/<bundle-id>/Data
        FileManager.default.homeDirectoryForCurrentUser
    }

    public static func containerDataDirectory(bundleId: String? = Bundle.main.bundleIdentifier) -> URL? {
        guard let bid = bundleId, !bid.isEmpty else { return nil }
        let p = realHomeDirectory()
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent(bid, isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
        if FileManager.default.fileExists(atPath: p.path) {
            return p
        }
        return nil
    }

    public static func isSandboxedProcess() -> Bool {
        let env = ProcessInfo.processInfo.environment
        if env["APP_SANDBOX_CONTAINER_ID"] != nil {
            return true
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if home.contains("/Library/Containers/") {
            return true
        }
        // Heuristic fallback: if a container exists for our bundle id, treat as sandboxed.
        if containerDataDirectory() != nil {
            return true
        }
        return false
    }

    public static func appGroupDirectory(groupId: String = SummaryStorage.appGroupId) -> URL? {
        // In signed/distributed builds we want a stable shared location so satellites (FA Tracker, etc)
        // can talk to the Hub without per-file security-scoped bookmarks.
        //
        // We keep a safety valve for dev/ad-hoc builds:
        // - If the user explicitly disables App Group storage, do not use it.
        // - If the build has no TeamIdentifier (common for ad-hoc dev builds), avoid touching App Group
        //   because some macOS versions can spam "would like to access data from other apps" prompts.
        if let v = UserDefaults.standard.object(forKey: "relflowhub_use_app_group_storage") as? Bool, v == false {
            return nil
        }
        if cachedTeamIdentifier == nil {
            return nil
        }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)
    }


    public static func hubDirectoryCandidates() -> [URL] {
        var out: [URL] = []

        if let g = appGroupDirectory() {
            out.append(g)
        }

        let useAppGroup = (appGroupDirectory() != nil)

        // Dev sandbox builds: prefer the app container directory (stable, no TCC spam).
        // NOTE: Some builds do not expose a container home via FileManager.homeDirectoryForCurrentUser,
        // so we also probe the canonical container path by bundle id.
        if !useAppGroup {
            if let cd = containerDataDirectory() {
                out.append(cd.appendingPathComponent("RELFlowHub", isDirectory: true))
            }
        }

        if isSandboxedProcess() && !useAppGroup {
            out.append(sandboxHomeDirectory().appendingPathComponent("RELFlowHub", isDirectory: true))
            out.append(URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("RELFlowHub", isDirectory: true))
            out.append(realHomeDirectory().appendingPathComponent("RELFlowHub", isDirectory: true))
        } else {
            out.append(realHomeDirectory().appendingPathComponent("RELFlowHub", isDirectory: true))
            out.append(sandboxHomeDirectory().appendingPathComponent("RELFlowHub", isDirectory: true))
        }

        // De-dup by path.
        var seen: Set<String> = []
        return out.filter {
            let p = $0.path
            if seen.contains(p) { return false }
            seen.insert(p)
            return true
        }
    }

    @discardableResult
    public static func ensureHubDirectory() -> URL {
        for dir in hubDirectoryCandidates() {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                return dir
            } catch {
                continue
            }
        }
        // Fall back to real home even if not writable; callers will surface bind/write errors.
        return realHomeDirectory().appendingPathComponent("RELFlowHub", isDirectory: true)
    }

    public static func ipcSocketPath() -> String {
        // If App Group is configured (typically requires a real signed build), use it.
        if let g = appGroupDirectory() {
            return g.appendingPathComponent(".rel_flow_hub.sock").path
        }

        // Prefer real user home for compatibility with existing tools.
        let homeDir = realHomeDirectory().appendingPathComponent("RELFlowHub", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: homeDir, withIntermediateDirectories: true)
            return homeDir.appendingPathComponent(".rel_flow_hub.sock").path
        } catch {
            // Fall back to /private/tmp. (Note: /tmp is a symlink to /private/tmp.)
            let tmpDir = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
                .appendingPathComponent("RELFlowHub", isDirectory: true)
            try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            return tmpDir.appendingPathComponent(".rel_flow_hub.sock").path
        }

    }

    /// A cross-process shared directory for IPC + lightweight state.
    ///
    /// Prefer App Group when available (properly signed builds), otherwise fall back to
    /// the real user home directory (`~/RELFlowHub`) so non-sandboxed clients/agents can
    /// read/write without needing access to the Hub's app container.
    @discardableResult
    public static func ensurePublicHubDirectory() -> URL {
        if let g = appGroupDirectory() {
            try? FileManager.default.createDirectory(at: g, withIntermediateDirectories: true)
            return g
        }

        // Sandboxed Hub builds cannot write to the real home directory reliably.
        // Use a shared tmp directory for cross-process communication.
        if isSandboxedProcess() {
            let tmp = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
                .appendingPathComponent("RELFlowHub", isDirectory: true)
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            return tmp
        }

        let dir = realHomeDirectory().appendingPathComponent("RELFlowHub", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
