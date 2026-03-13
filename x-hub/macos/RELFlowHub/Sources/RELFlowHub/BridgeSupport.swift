import Foundation
import AppKit
import RELFlowHubCore

@MainActor
final class BridgeSupport: ObservableObject {
    static let shared = BridgeSupport()

    @Published private(set) var bridgeStatusText: String = "Bridge: unknown"

    struct BridgeStatusSnapshot: Equatable {
        var alive: Bool
        var updatedAt: Double
        var enabledUntil: Double

        var enabled: Bool {
            enabledUntil > Date().timeIntervalSince1970
        }

        var looksPersistent: Bool {
            enabledUntil - Date().timeIntervalSince1970 > 7 * 24 * 60 * 60
        }
    }

    private var timer: Timer?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        refresh()
    }

    func refresh() {
        let st = statusSnapshot()
        if !st.alive {
            bridgeStatusText = "Bridge: off"
            return
        }
        if st.enabledUntil > Date().timeIntervalSince1970 {
            if st.looksPersistent {
                bridgeStatusText = "Bridge: on"
                return
            }
            let rem = Int(max(0, st.enabledUntil - Date().timeIntervalSince1970))
            bridgeStatusText = "Bridge: on (\(rem)s)"
            return
        }
        bridgeStatusText = "Bridge: disabled"
    }

    func statusSnapshot(ttl: Double = 3.0, now: Double = Date().timeIntervalSince1970) -> BridgeStatusSnapshot {
        if let st = BridgePathResolver.bestStatus(ttl: ttl, now: now) {
            return BridgeStatusSnapshot(alive: st.alive, updatedAt: st.updatedAt, enabledUntil: st.enabledUntil)
        }
        return BridgeStatusSnapshot(alive: false, updatedAt: 0, enabledUntil: 0)
    }

    func enable(seconds: Int) {
        let current = statusSnapshot()
        let until = max(
            current.enabledUntil,
            Date().timeIntervalSince1970 + Double(max(10, seconds))
        )
        let obj: [String: Any] = [
            "enabled_until": until,
            "updated_at": Date().timeIntervalSince1970,
        ]

        let targets = candidateDirsForControlWrite()
        for base in targets {
            let settingsFile = base.appendingPathComponent("bridge_settings.json")
            let commandsDir = base.appendingPathComponent("bridge_commands", isDirectory: true)
            try? FileManager.default.createDirectory(at: commandsDir, withIntermediateDirectories: true)
            if let data = try? JSONSerialization.data(withJSONObject: obj, options: []) {
                try? data.write(to: settingsFile, options: .atomic)
            }
            enqueueCommand(["type": "enable_until", "enabled_until": until], commandsDir: commandsDir)
        }
    }

    func disable() {
        let targets = candidateDirsForControlWrite()
        for base in targets {
            let settingsFile = base.appendingPathComponent("bridge_settings.json")
            let commandsDir = base.appendingPathComponent("bridge_commands", isDirectory: true)
            try? FileManager.default.createDirectory(at: commandsDir, withIntermediateDirectories: true)
            enqueueCommand(["type": "stop"], commandsDir: commandsDir)
            try? FileManager.default.removeItem(at: settingsFile)
        }
    }

    func openBridgeApp() {
        // Single-app mode: bridge service is embedded in Hub.
        // Keep this API for backward compatibility, but avoid opening external apps.
        refresh()
    }

    private func candidateDirsForControlWrite() -> [URL] {
        var dirs = BridgePathResolver.candidateBaseDirs()
        let preferred = BridgePathResolver.preferredBaseDirForWrites()
        dirs.removeAll { $0.path == preferred.path }
        dirs.insert(preferred, at: 0)
        return dirs
    }

    private func enqueueCommand(_ obj: [String: Any], commandsDir: URL) {
        let tmp = commandsDir.appendingPathComponent(".cmd_\(UUID().uuidString).tmp")
        let out = commandsDir.appendingPathComponent("cmd_\(UUID().uuidString).json")
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: []) {
            try? data.write(to: tmp, options: .atomic)
            try? FileManager.default.moveItem(at: tmp, to: out)
        }
    }
}
