import Foundation

enum RustHubHTTPAccess {
    private static let cacheLock = NSLock()
    private static let cacheTTL: TimeInterval = 5
    private static var cached: (checkedAt: Date, value: String?)?

    static func applyAccessKey(to request: inout URLRequest) {
        guard let key = cachedAccessKey() else { return }
        applyAccessKey(key, to: &request)
    }

    static func applyAccessKey(
        to request: inout URLRequest,
        environment: [String: String],
        baseDirs: [URL]? = nil
    ) {
        guard let key = accessKey(environment: environment, baseDirs: baseDirs) else { return }
        applyAccessKey(key, to: &request)
    }

    private static func applyAccessKey(_ key: String, to request: inout URLRequest) {
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(key, forHTTPHeaderField: "X-XHub-Access-Key")
    }

    static func accessKey(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        baseDirs: [URL]? = nil
    ) -> String? {
        for key in ["XHUB_RUST_HTTP_ACCESS_KEY", "XHUB_RUST_HUB_ACCESS_KEY"] {
            if let value = nonEmpty(environment[key]) {
                return value
            }
        }

        for key in ["XHUB_RUST_HTTP_ACCESS_KEY_FILE", "XHUB_RUST_HUB_ACCESS_KEY_FILE"] {
            guard let path = nonEmpty(environment[key]) else { continue }
            if let value = readAccessKeyFile(URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)) {
                return value
            }
        }

        for root in baseDirs ?? candidateBaseDirs() {
            for file in candidateAccessKeyFiles(root: root) {
                if let value = readAccessKeyFile(file) {
                    return value
                }
            }
        }
        return nil
    }

    static func resetCacheForTesting() {
        cacheLock.lock()
        cached = nil
        cacheLock.unlock()
    }

    private static func cachedAccessKey() -> String? {
        let now = Date()
        cacheLock.lock()
        if let entry = cached,
           now.timeIntervalSince(entry.checkedAt) >= 0,
           now.timeIntervalSince(entry.checkedAt) <= cacheTTL {
            let value = entry.value
            cacheLock.unlock()
            return value
        }
        cacheLock.unlock()

        let value = accessKey()
        cacheLock.lock()
        cached = (checkedAt: now, value: value)
        cacheLock.unlock()
        return value
    }

    private static func candidateBaseDirs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let rustHubRoot = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("AX", isDirectory: true)
            .appendingPathComponent("rust-hub", isDirectory: true)

        var roots: [URL] = [
            HubPaths.baseDir(),
            rustHubRoot.appendingPathComponent("local", isDirectory: true),
            rustHubRoot.appendingPathComponent("domain", isDirectory: true),
            rustHubRoot.appendingPathComponent("lan", isDirectory: true)
        ]

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        roots.append(cwd)
        roots.append(cwd.appendingPathComponent("rust/xhubd", isDirectory: true))
        roots.append(cwd.appendingPathComponent("x-hub-system/rust/xhubd", isDirectory: true))

        var seen = Set<String>()
        return roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func candidateAccessKeyFiles(root: URL) -> [URL] {
        [
            "config/xhubd_http_access_key",
            "config/xhubd_domain_access_key",
            "config/xhubd_lan_access_key",
            "secrets/xhubd_http_access_key",
            "secrets/xhubd_domain_access_key",
            "secrets/xhubd_lan_access_key"
        ].map { root.appendingPathComponent($0) }
    }

    private static func readAccessKeyFile(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              let value = nonEmpty(text) else {
            return nil
        }
        return value
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
