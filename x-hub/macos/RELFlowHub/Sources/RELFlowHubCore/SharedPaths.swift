import Foundation
import Darwin
import Security

public enum SharedPaths {
    public static let preferredRuntimeDirectoryName = "XHub"
    public static let legacyRuntimeDirectoryName = "RELFlowHub"
    public static let runtimeDirectoryAliases = [preferredRuntimeDirectoryName, legacyRuntimeDirectoryName]
    private static let sourceRunHomeOverrideEnvKey = "XHUB_SOURCE_RUN_HOME"

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

    private static func sourceRunHomeOverride() -> URL? {
        let rawValue = ProcessInfo.processInfo.environment[sourceRunHomeOverrideEnvKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawValue.isEmpty else { return nil }
        let expandedPath = NSString(string: rawValue).expandingTildeInPath
        guard !expandedPath.isEmpty else { return nil }
        return URL(fileURLWithPath: expandedPath, isDirectory: true)
    }

    private static func appendHomeCandidate(_ rawPath: String?, into candidates: inout [URL], seen: inout Set<String>) {
        let trimmed = (rawPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        guard !expanded.isEmpty else { return }
        let url = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        guard seen.insert(url.path).inserted else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return
        }
        candidates.append(url)
    }

    private static func isContainerizedHomePath(_ path: String) -> Bool {
        path.contains("/Library/Containers/")
    }

    public static func guessedRealUserHomeDirectory() -> URL? {
        let username = NSUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else { return nil }
        return URL(fileURLWithPath: "/Users/\(username)", isDirectory: true)
    }

    private static func realHomeDirectoryCandidates() -> [URL] {
        var candidates: [URL] = []
        var seen: Set<String> = []

        appendHomeCandidate(NSHomeDirectoryForUser(NSUserName()), into: &candidates, seen: &seen)

        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            appendHomeCandidate(String(cString: dir), into: &candidates, seen: &seen)
        }

        if let guessed = guessedRealUserHomeDirectory() {
            appendHomeCandidate(guessed.path, into: &candidates, seen: &seen)
        }

        appendHomeCandidate(FileManager.default.homeDirectoryForCurrentUser.path, into: &candidates, seen: &seen)
        return candidates
    }

    // In App Sandbox, FileManager.homeDirectoryForCurrentUser points to the container.
    // For IPC with non-sandboxed tools, we need the real user home directory.
    public static func realHomeDirectory() -> URL {
        if let override = sourceRunHomeOverride() {
            return override
        }
        let candidates = realHomeDirectoryCandidates()
        if let nonContainer = candidates.first(where: { !isContainerizedHomePath($0.path) }) {
            return nonContainer
        }
        if let first = candidates.first {
            return first
        }
        // Fallback: may still be container under sandbox, but better than crashing.
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static func sandboxHomeDirectory() -> URL {
        if let override = sourceRunHomeOverride() {
            return override
        }
        // Under App Sandbox this is typically: ~/Library/Containers/<bundle-id>/Data
        return FileManager.default.homeDirectoryForCurrentUser
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

    private static func runtimeDirectories(in base: URL) -> [URL] {
        runtimeDirectoryAliases.map { base.appendingPathComponent($0, isDirectory: true) }
    }

    private static func legacyRuntimeDirectory(in base: URL) -> URL {
        base.appendingPathComponent(legacyRuntimeDirectoryName, isDirectory: true)
    }

    public static func hubDirectoryCandidates() -> [URL] {
        var out: [URL] = []

        let groupDir = appGroupDirectory()
        if let g = groupDir {
            out.append(g)
        }

        let useAppGroup = (groupDir != nil)

        // Dev sandbox builds: prefer the app container directory (stable, no TCC spam).
        // NOTE: Some builds do not expose a container home via FileManager.homeDirectoryForCurrentUser,
        // so we also probe the canonical container path by bundle id.
        if !useAppGroup {
            if let cd = containerDataDirectory() {
                out.append(contentsOf: runtimeDirectories(in: cd))
            }
        }

        if isSandboxedProcess() && !useAppGroup {
            out.append(contentsOf: runtimeDirectories(in: sandboxHomeDirectory()))
            out.append(contentsOf: runtimeDirectories(in: URL(fileURLWithPath: "/private/tmp", isDirectory: true)))
            out.append(contentsOf: runtimeDirectories(in: realHomeDirectory()))
        } else {
            out.append(contentsOf: runtimeDirectories(in: realHomeDirectory()))
            out.append(contentsOf: runtimeDirectories(in: sandboxHomeDirectory()))
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
        let groupDir = appGroupDirectory()
        let useAppGroup = (groupDir != nil)
        var writeCandidates: [URL] = []
        if let groupDir {
            writeCandidates.append(groupDir)
        }
        if !useAppGroup, let cd = containerDataDirectory() {
            writeCandidates.append(legacyRuntimeDirectory(in: cd))
        }
        if isSandboxedProcess() && !useAppGroup {
            writeCandidates.append(legacyRuntimeDirectory(in: sandboxHomeDirectory()))
            writeCandidates.append(legacyRuntimeDirectory(in: URL(fileURLWithPath: "/private/tmp", isDirectory: true)))
            writeCandidates.append(legacyRuntimeDirectory(in: realHomeDirectory()))
        } else {
            writeCandidates.append(legacyRuntimeDirectory(in: realHomeDirectory()))
            writeCandidates.append(legacyRuntimeDirectory(in: sandboxHomeDirectory()))
        }

        var seen: Set<String> = []
        for dir in writeCandidates where seen.insert(dir.path).inserted {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                return dir
            } catch {
                continue
            }
        }
        // Fall back to real home even if not writable; callers will surface bind/write errors.
        return legacyRuntimeDirectory(in: realHomeDirectory())
    }

    public static func ipcSocketPath() -> String {
        // If App Group is configured (typically requires a real signed build), use it.
        if let g = appGroupDirectory() {
            return g.appendingPathComponent(".rel_flow_hub.sock").path
        }

        // Prefer real user home for compatibility with existing tools.
        let homeDir = legacyRuntimeDirectory(in: realHomeDirectory())
        do {
            try FileManager.default.createDirectory(at: homeDir, withIntermediateDirectories: true)
            return homeDir.appendingPathComponent(".rel_flow_hub.sock").path
        } catch {
            // Fall back to /private/tmp. (Note: /tmp is a symlink to /private/tmp.)
            let tmpDir = legacyRuntimeDirectory(in: URL(fileURLWithPath: "/private/tmp", isDirectory: true))
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
            let tmp = legacyRuntimeDirectory(in: URL(fileURLWithPath: "/private/tmp", isDirectory: true))
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            return tmp
        }

        let dir = legacyRuntimeDirectory(in: realHomeDirectory())
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The embedded Bridge runs inside the Hub app itself, so its heartbeat/control files
    /// should prefer the Hub's own writable runtime directory instead of `/private/tmp`.
    ///
    /// This avoids sandbox write failures where the Hub can update its own launch status in
    /// the app container but silently fails to publish bridge heartbeats to the public dir.
    @discardableResult
    public static func ensureEmbeddedBridgeDirectory(bundleId: String? = Bundle.main.bundleIdentifier) -> URL {
        if let g = appGroupDirectory() {
            try? FileManager.default.createDirectory(at: g, withIntermediateDirectories: true)
            return g
        }

        if isSandboxedProcess(),
           let container = containerDataDirectory(bundleId: bundleId) {
            let dir = legacyRuntimeDirectory(in: container)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }

        return ensureHubDirectory()
    }
}
