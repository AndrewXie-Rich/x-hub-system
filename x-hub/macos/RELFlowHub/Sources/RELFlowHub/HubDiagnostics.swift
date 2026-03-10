import Foundation
import RELFlowHubCore

enum HubDiagnostics {
    static func log(_ msg: String) {
        let base = SharedPaths.ensureHubDirectory()
        let url = base.appendingPathComponent("hub_debug.log")
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }

        // Best-effort append.
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                let fh = try FileHandle(forWritingTo: url)
                try fh.seekToEnd()
                try fh.write(contentsOf: data)
                try fh.close()
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            // Swallow.
        }
    }
}

