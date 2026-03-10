import Foundation

enum BridgeFetchIPC {
    struct FetchResult {
        var ok: Bool
        var status: Int
        var text: String
        var error: String
    }

    enum IPCError: LocalizedError {
        case bridgeNotRunning
        case bridgeNotEnabled
        case writeFailed
        case timeout
        case badResponse

        var errorDescription: String? {
            switch self {
            case .bridgeNotRunning:
                return "Bridge is not running. Open Settings -> Networking (Bridge) -> Open Bridge, then retry."
            case .bridgeNotEnabled:
                return "Bridge networking is disabled. Open Settings -> Networking (Bridge) and click Enable 30 min, then retry."
            case .writeFailed:
                return "Failed to write bridge request."
            case .timeout:
                return "Bridge request timed out. Ensure Bridge is running and enabled, then retry."
            case .badResponse:
                return "Bridge returned an invalid response."
            }
        }
    }

    static func fetch(
        url: URL,
        headers: [String: String],
        timeoutSec: Double,
        maxBytes: Int = 1_500_000
    ) async throws -> FetchResult {
        guard let st = await waitForBridgeReady(timeoutSec: 2.5) else {
            throw IPCError.bridgeNotRunning
        }
        if !st.alive {
            throw IPCError.bridgeNotRunning
        }
        if !st.enabled {
            throw IPCError.bridgeNotEnabled
        }

        let baseDir = st.baseDir
        let reqDir = baseDir.appendingPathComponent("bridge_requests", isDirectory: true)
        let respDir = baseDir.appendingPathComponent("bridge_responses", isDirectory: true)

        try? FileManager.default.createDirectory(at: reqDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: respDir, withIntermediateDirectories: true)

        let reqId = UUID().uuidString
        let reqURL = reqDir.appendingPathComponent("req_\(reqId).json")
        let respURL = respDir.appendingPathComponent("resp_\(reqId).json")

        var safeHeaders: [String: String] = [:]
        for (k0, v0) in headers {
            let key = k0.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty || key.contains("\n") || key.contains("\r") { continue }
            let value = v0.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty || value.contains("\n") || value.contains("\r") { continue }
            safeHeaders[key] = value
        }

        let reqObj: [String: Any] = [
            "type": "fetch",
            "req_id": reqId,
            "url": url.absoluteString,
            "method": "GET",
            "headers": safeHeaders,
            "timeout_sec": max(2.0, min(60.0, timeoutSec)),
            "max_bytes": max(1_024, maxBytes),
            "created_at": Date().timeIntervalSince1970,
        ]

        do {
            try writeJSONAtomic(reqObj, to: reqURL)
        } catch {
            throw IPCError.writeFailed
        }
        defer { try? FileManager.default.removeItem(at: reqURL) }

        let waitSec = max(3.0, min(120.0, timeoutSec + 8.0))
        let deadline = Date().timeIntervalSince1970 + waitSec
        while Date().timeIntervalSince1970 < deadline {
            if let data = try? Data(contentsOf: respURL), !data.isEmpty {
                defer { try? FileManager.default.removeItem(at: respURL) }
                guard let obj = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
                    throw IPCError.badResponse
                }
                guard String(describing: obj["req_id"] ?? "") == reqId else {
                    throw IPCError.badResponse
                }
                return FetchResult(
                    ok: boolValue(obj["ok"]),
                    status: intValue(obj["status"]),
                    text: String(describing: obj["text"] ?? ""),
                    error: String(describing: obj["error"] ?? "")
                )
            }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }

        throw IPCError.timeout
    }

    private static func waitForBridgeReady(timeoutSec: Double) async -> BridgePathResolver.StatusSnapshot? {
        let deadline = Date().timeIntervalSince1970 + max(0.2, timeoutSec)
        var best = BridgePathResolver.bestStatus(ttl: 120.0)

        while Date().timeIntervalSince1970 < deadline {
            if let st = BridgePathResolver.bestStatus(ttl: 3.5), st.alive {
                return st
            }
            if best == nil {
                best = BridgePathResolver.bestStatus(ttl: 120.0)
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        return BridgePathResolver.bestStatus(ttl: 3.5) ?? best
    }

    private static func writeJSONAtomic(_ obj: [String: Any], to out: URL) throws {
        let dir = out.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let tmp = dir.appendingPathComponent(".tmp_\(UUID().uuidString).json")
        let data = try JSONSerialization.data(withJSONObject: obj, options: [])
        try data.write(to: tmp)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        try FileManager.default.moveItem(at: tmp, to: out)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: out.path)
    }

    private static func intValue(_ any: Any?) -> Int {
        if let v = any as? Int { return v }
        if let v = any as? Double { return Int(v) }
        if let v = any as? NSNumber { return v.intValue }
        if let s = any as? String, let v = Int(s) { return v }
        return 0
    }

    private static func boolValue(_ any: Any?) -> Bool {
        if let v = any as? Bool { return v }
        if let v = any as? NSNumber { return v.boolValue }
        if let s = any as? String {
            let v = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return v == "1" || v == "true" || v == "yes"
        }
        return false
    }
}
