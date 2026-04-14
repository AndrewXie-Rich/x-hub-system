import Foundation

enum HubBridgeClient {
    struct BridgeStatus: Equatable {
        var alive: Bool
        var enabledUntil: Double
        var requestQueued: Bool? = nil
        var requestError: String = ""

        var enabled: Bool {
            enabledUntil > Date().timeIntervalSince1970
        }
    }

    private static let testingLock = NSLock()
    private static var baseDirOverrideForTesting: URL?
    private static var commandWriteOverrideForTesting: (@Sendable (Data, URL, URL) throws -> Void)?

    static func status() -> BridgeStatus {
        let base = bridgeBaseDir()
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
        let base = bridgeBaseDir()
        let settingsFile = base.appendingPathComponent("bridge_settings.json")
        let commandsDir = base.appendingPathComponent("bridge_commands", isDirectory: true)
        try? FileManager.default.createDirectory(at: commandsDir, withIntermediateDirectories: true)

        let until = Date().timeIntervalSince1970 + Double(max(10, seconds))
        var requestQueued: Bool? = nil
        var requestErrors: [String] = []
        let obj: [String: Any] = [
            "enabled_until": until,
            "updated_at": Date().timeIntervalSince1970,
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [])
            try XTStoreWriteSupport.writeSnapshotData(data, to: settingsFile)
        } catch {
            requestErrors.append("bridge_settings_write_failed=\(summarized(error))")
        }

        // Drop a command file for fast pickup.
        let cmd: [String: Any] = ["type": "enable_until", "enabled_until": until]
        let tmp = commandsDir.appendingPathComponent(".cmd_\(UUID().uuidString).tmp")
        let out = commandsDir.appendingPathComponent("cmd_\(UUID().uuidString).json")
        do {
            let data = try JSONSerialization.data(withJSONObject: cmd, options: [])
            try writeCommandData(data, tmp: tmp, out: out)
            requestQueued = true
        } catch {
            requestQueued = false
            requestErrors.append("bridge_enable_command_write_failed=\(summarized(error))")
        }

        // Wait briefly for the Bridge heartbeat to show up.
        let deadline = Date().addingTimeInterval(3.5)
        while Date() < deadline {
            let st = status()
            if st.alive {
                return st.settingRequestState(
                    queued: requestQueued,
                    error: requestErrors.joined(separator: " | ")
                )
            }
            Thread.sleep(forTimeInterval: 0.12)
        }

        return status().settingRequestState(
            queued: requestQueued,
            error: requestErrors.joined(separator: " | ")
        )
    }

    static func installBaseDirOverrideForTesting(_ url: URL?) {
        withTestingLock {
            baseDirOverrideForTesting = url
        }
    }

    static func installCommandWriteOverrideForTesting(
        _ override: (@Sendable (Data, URL, URL) throws -> Void)?
    ) {
        withTestingLock {
            commandWriteOverrideForTesting = override
        }
    }

    static func resetForTesting() {
        withTestingLock {
            baseDirOverrideForTesting = nil
            commandWriteOverrideForTesting = nil
        }
    }

    private static func bridgeBaseDir() -> URL {
        if let override = withTestingLock({ baseDirOverrideForTesting }) {
            return override
        }
        return HubBridgePaths.bridgeBaseDir()
    }

    private static func writeCommandData(_ data: Data, tmp: URL, out: URL) throws {
        if let override = withTestingLock({ commandWriteOverrideForTesting }) {
            try override(data, tmp, out)
            return
        }
        try data.write(to: tmp, options: .atomic)
        try FileManager.default.moveItem(at: tmp, to: out)
    }

    private static func summarized(_ error: Error) -> String {
        "\(type(of: error)):\(error.localizedDescription)"
    }

    @discardableResult
    private static func withTestingLock<T>(_ body: () -> T) -> T {
        testingLock.lock()
        defer { testingLock.unlock() }
        return body()
    }
}

private extension HubBridgeClient.BridgeStatus {
    func settingRequestState(queued: Bool?, error: String) -> Self {
        var copy = self
        copy.requestQueued = queued
        copy.requestError = error
        return copy
    }
}
