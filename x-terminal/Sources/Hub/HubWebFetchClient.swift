import Foundation

enum HubWebFetchClient {
    struct FetchResult: Equatable {
        var ok: Bool
        var status: Int
        var finalURL: String
        var contentType: String
        var truncated: Bool
        var bytes: Int
        var text: String
        var error: String
    }

    static func fetch(url: String, timeoutSec: Double = 12.0, maxBytes: Int = 1_000_000) throws -> FetchResult {
        let base = HubBridgePaths.bridgeBaseDir()
        let reqDir = base.appendingPathComponent("bridge_requests", isDirectory: true)
        let respDir = base.appendingPathComponent("bridge_responses", isDirectory: true)
        try? FileManager.default.createDirectory(at: reqDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: respDir, withIntermediateDirectories: true)

        let rid = UUID().uuidString
        let reqURL = reqDir.appendingPathComponent("req_\(rid).json")
        let tmpURL = reqDir.appendingPathComponent(".req_\(rid).tmp")
        let respURL = respDir.appendingPathComponent("resp_\(rid).json")

        let obj: [String: Any] = [
            "type": "fetch",
            "req_id": rid,
            "url": url,
            "method": "GET",
            "created_at": Date().timeIntervalSince1970,
            "timeout_sec": max(2.0, min(60.0, timeoutSec)),
            "max_bytes": max(1024, min(5_000_000, maxBytes)),
        ]
        let data = try JSONSerialization.data(withJSONObject: obj, options: [])
        try data.write(to: tmpURL, options: .atomic)
        try FileManager.default.moveItem(at: tmpURL, to: reqURL)

        // Poll for response.
        let deadline = Date().addingTimeInterval(max(3.0, timeoutSec + 10.0))
        while Date() < deadline {
            if let d = try? Data(contentsOf: respURL),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                let ok = (o["ok"] as? Bool) ?? false
                let status = (o["status"] as? Int) ?? 0
                let finalURL = (o["final_url"] as? String) ?? ""
                let ct = (o["content_type"] as? String) ?? ""
                let truncated = (o["truncated"] as? Bool) ?? false
                let bytes = (o["bytes"] as? Int) ?? 0
                let text = (o["text"] as? String) ?? ""
                let err = (o["error"] as? String) ?? ""

                // Best-effort cleanup.
                try? FileManager.default.removeItem(at: respURL)

                return FetchResult(ok: ok, status: status, finalURL: finalURL, contentType: ct, truncated: truncated, bytes: bytes, text: text, error: err)
            }

            Thread.sleep(forTimeInterval: 0.08)
        }

        throw NSError(domain: "xterminal", code: 408, userInfo: [NSLocalizedDescriptionKey: "web_fetch timeout"])
    }
}
