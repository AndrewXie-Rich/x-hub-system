import Foundation

enum HubPaths {
    private static let lock = DispatchQueue(label: "xterminal.hubpaths")
    private static var _baseDirOverride: URL? = nil

    static func setBaseDirOverride(_ url: URL?) {
        lock.sync {
            _baseDirOverride = url
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
        let home = FileManager.default.homeDirectoryForCurrentUser

        // Match FA Tracker's vendored relflowhub_ipc.py default selection.
        let cont = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent("com.rel.flowhub", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("RELFlowHub", isDirectory: true)
        if FileManager.default.fileExists(atPath: cont.path) {
            return cont
        }

        let tmp = URL(fileURLWithPath: "/private/tmp/RELFlowHub", isDirectory: true)
        if FileManager.default.fileExists(atPath: tmp.path) {
            return tmp
        }

        let legacy = home.appendingPathComponent("RELFlowHub", isDirectory: true)
        if FileManager.default.fileExists(atPath: legacy.path) {
            return legacy
        }

        return home.appendingPathComponent("Library/Group Containers/group.rel.flowhub")
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
