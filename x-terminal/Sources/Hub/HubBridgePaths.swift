import Foundation

enum HubBridgePaths {
    static func bridgeBaseDir() -> URL {
        let publicCandidates = [
            URL(fileURLWithPath: "/private/tmp/XHub", isDirectory: true),
            URL(fileURLWithPath: "/private/tmp/RELFlowHub", isDirectory: true),
        ]

        for candidate in publicCandidates {
            let st = candidate.appendingPathComponent("bridge_status.json")
            if let data = try? Data(contentsOf: st),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let updatedAt = obj["updatedAt"] as? Double,
               (Date().timeIntervalSince1970 - updatedAt) < 5.0 {
                return candidate
            }
        }

        // BridgeRunner uses the public /tmp contract in ad-hoc/sandbox builds.
        // Prefer it by default so "request enable" can bootstrap Bridge even before
        // the first heartbeat appears.
        for candidate in publicCandidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        let hubDir = HubPaths.baseDir()
        let hubStatus = hubDir.appendingPathComponent("bridge_status.json")
        if let data = try? Data(contentsOf: hubStatus),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let updatedAt = obj["updatedAt"] as? Double,
           (Date().timeIntervalSince1970 - updatedAt) < 5.0 {
            return hubDir
        }

        // Keep the legacy /private/tmp contract as the default write location until
        // the runtime identity migration is fully completed.
        return publicCandidates[1]
    }
}
