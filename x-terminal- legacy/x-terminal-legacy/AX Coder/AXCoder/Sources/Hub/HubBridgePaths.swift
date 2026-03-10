import Foundation

enum HubBridgePaths {
    static func bridgeBaseDir() -> URL {
        let publicDir = URL(fileURLWithPath: "/private/tmp/RELFlowHub", isDirectory: true)
        let st = publicDir.appendingPathComponent("bridge_status.json")
        if let data = try? Data(contentsOf: st),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let updatedAt = obj["updatedAt"] as? Double {
            if (Date().timeIntervalSince1970 - updatedAt) < 5.0 {
                return publicDir
            }
        }

        // BridgeRunner uses the public /tmp contract in ad-hoc/sandbox builds.
        // Prefer it by default so "request enable" can bootstrap Bridge even before
        // the first heartbeat appears.
        if FileManager.default.fileExists(atPath: publicDir.path) {
            return publicDir
        }

        let hubDir = HubPaths.baseDir()
        let hubStatus = hubDir.appendingPathComponent("bridge_status.json")
        if let data = try? Data(contentsOf: hubStatus),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let updatedAt = obj["updatedAt"] as? Double,
           (Date().timeIntervalSince1970 - updatedAt) < 5.0 {
            return hubDir
        }

        return publicDir
    }
}
