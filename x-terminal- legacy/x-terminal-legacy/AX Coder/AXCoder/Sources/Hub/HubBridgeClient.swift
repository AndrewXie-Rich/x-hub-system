import AppKit
import Foundation

enum HubBridgeClient {
    struct BridgeStatus: Equatable {
        var alive: Bool
        var enabledUntil: Double

        var enabled: Bool {
            enabledUntil > Date().timeIntervalSince1970
        }
    }

    static func status() -> BridgeStatus {
        let base = HubBridgePaths.bridgeBaseDir()
        let url = base.appendingPathComponent("bridge_status.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return BridgeStatus(alive: false, enabledUntil: 0)
        }
        let updatedAt = (obj["updatedAt"] as? Double) ?? 0
        let alive = (Date().timeIntervalSince1970 - updatedAt) < 3.0
        let enabledUntil = (obj["enabledUntil"] as? Double) ?? 0
        return BridgeStatus(alive: alive, enabledUntil: enabledUntil)
    }

    static func requestEnable(seconds: Int) -> BridgeStatus {
        launchBridgeAppIfInstalled()

        let base = HubBridgePaths.bridgeBaseDir()
        let settingsFile = base.appendingPathComponent("bridge_settings.json")
        let commandsDir = base.appendingPathComponent("bridge_commands", isDirectory: true)
        try? FileManager.default.createDirectory(at: commandsDir, withIntermediateDirectories: true)

        let until = Date().timeIntervalSince1970 + Double(max(10, seconds))
        let obj: [String: Any] = [
            "enabled_until": until,
            "updated_at": Date().timeIntervalSince1970,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: []) {
            try? data.write(to: settingsFile, options: .atomic)
        }

        // Drop a command file for fast pickup.
        let cmd: [String: Any] = ["type": "enable_until", "enabled_until": until]
        let tmp = commandsDir.appendingPathComponent(".cmd_\(UUID().uuidString).tmp")
        let out = commandsDir.appendingPathComponent("cmd_\(UUID().uuidString).json")
        if let data = try? JSONSerialization.data(withJSONObject: cmd, options: []) {
            try? data.write(to: tmp, options: .atomic)
            try? FileManager.default.moveItem(at: tmp, to: out)
        }

        // Wait briefly for the Bridge heartbeat to show up.
        let deadline = Date().addingTimeInterval(3.5)
        while Date() < deadline {
            let st = status()
            if st.alive {
                return st
            }
            Thread.sleep(forTimeInterval: 0.12)
        }

        return status()
    }

    private static func launchBridgeAppIfInstalled() {
        let launch: () -> Void = {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.rel.flowhub.bridge") {
                NSWorkspace.shared.open(url)
            }
        }
        if Thread.isMainThread {
            launch()
        } else {
            DispatchQueue.main.async(execute: launch)
        }
    }
}
