import Foundation
import RELFlowHubCore

// Embedded networking helper running inside the Hub app.
// It preserves the same filesystem IPC contract as RELFlowHubBridge.

@MainActor
final class EmbeddedBridgeRunner {
    private static let defaultAlwaysOnSeconds: Double = 10 * 365 * 24 * 60 * 60

    private var heartbeatTimer: Timer?
    private var commandTimer: Timer?
    private var enabledUntil: Double = 0
    private var operatorDisabled: Bool = false
    private let startedAt = Date().timeIntervalSince1970

    // Embedded Bridge runs inside the Hub app process, so prefer the Hub's own runtime
    // directory. Using the public tmp dir here can fail silently under App Sandbox, which
    // leaves Hub launch status alive while bridge heartbeats never appear.
    private let baseDir: URL
    private let statusFile: URL
    private let settingsFile: URL
    private let commandsDir: URL
    private let requestsDir: URL
    private let responsesDir: URL
    private let auditFile: URL

    private var requestTimer: Timer?
    private var activeWebFetchCount: Int = 0
    private var activeAIGenerateCount: Int = 0

    init() {
        baseDir = SharedPaths.ensureEmbeddedBridgeDirectory()
        statusFile = baseDir.appendingPathComponent("bridge_status.json")
        settingsFile = baseDir.appendingPathComponent("bridge_settings.json")
        commandsDir = baseDir.appendingPathComponent("bridge_commands", isDirectory: true)
        requestsDir = baseDir.appendingPathComponent("bridge_requests", isDirectory: true)
        responsesDir = baseDir.appendingPathComponent("bridge_responses", isDirectory: true)
        auditFile = baseDir.appendingPathComponent("bridge_audit.log")
    }

    func start() {
        try? FileManager.default.createDirectory(at: commandsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: requestsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: responsesDir, withIntermediateDirectories: true)
        enabledUntil = Self.defaultEnabledUntil(now: Date().timeIntervalSince1970)
        writeAudit("bridge_start")
        writeAudit("bridge_scheduler total=\(maxConcurrentTotal) fetch=\(maxConcurrentWebFetch) ai=\(maxConcurrentAIGenerate)")

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        commandTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.drainCommandsOnce()
            }
        }

        // Handle fetch requests.
        requestTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.drainRequestsOnce()
            }
        }
        tick()
    }

    func stop() {
        writeAudit("bridge_stop")
        heartbeatTimer?.invalidate()
        commandTimer?.invalidate()
        requestTimer?.invalidate()
        heartbeatTimer = nil
        commandTimer = nil
        requestTimer = nil
    }

    func statusText() -> String {
        if enabledUntil <= 0 {
            return "off"
        }
        if enabledUntil - Date().timeIntervalSince1970 > 7 * 24 * 60 * 60 {
            return "on"
        }
        let rem = Int(max(0, enabledUntil - Date().timeIntervalSince1970))
        return "on (\(rem)s left)"
    }

    private static func defaultEnabledUntil(now: Double) -> Double {
        now + defaultAlwaysOnSeconds
    }

    private var activeRequestTotal: Int {
        activeWebFetchCount + activeAIGenerateCount
    }

    private var maxConcurrentTotal: Int {
        envInt("RELFLOWHUB_BRIDGE_MAX_CONCURRENT_TOTAL", defaultValue: 6, minValue: 1, maxValue: 64)
    }

    private var maxConcurrentWebFetch: Int {
        envInt("RELFLOWHUB_BRIDGE_MAX_CONCURRENT_FETCH", defaultValue: 2, minValue: 1, maxValue: 32)
    }

    private var maxConcurrentAIGenerate: Int {
        envInt("RELFLOWHUB_BRIDGE_MAX_CONCURRENT_AI", defaultValue: 4, minValue: 1, maxValue: 32)
    }

    private func envInt(_ key: String, defaultValue: Int, minValue: Int, maxValue: Int) -> Int {
        let raw = ProcessInfo.processInfo.environment[key] ?? ""
        guard let parsed = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return max(minValue, min(maxValue, defaultValue))
        }
        return max(minValue, min(maxValue, parsed))
    }

    private func tick() {
        let now = Date().timeIntervalSince1970
        var loadedEnabledUntil: Double?
        if let data = try? Data(contentsOf: settingsFile),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let v = obj["enabled_until"] as? Double {
                loadedEnabledUntil = v
            } else if let v = obj["enabled_until"] as? Int {
                loadedEnabledUntil = Double(v)
            }
        }

        if operatorDisabled {
            enabledUntil = 0
        } else {
            let defaultUntil = Self.defaultEnabledUntil(now: now)
            if let loaded = loadedEnabledUntil, loaded > 0 {
                enabledUntil = max(enabledUntil, loaded, defaultUntil)
            } else if enabledUntil <= 0 || now > enabledUntil {
                enabledUntil = defaultUntil
            }
        }

        // Heartbeat for the core Hub.
        let st: [String: Any] = [
            "pid": Int(getpid()),
            "startedAt": startedAt,
            "updatedAt": Date().timeIntervalSince1970,
            "enabledUntil": enabledUntil,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: st, options: []) {
            try? data.write(to: statusFile, options: .atomic)
        }
    }

    private func writeAudit(_ event: String) {
        let line = "\(Date().timeIntervalSince1970)\t\(event)\n"
        if let data = line.data(using: .utf8) {
            if let fh = try? FileHandle(forWritingTo: auditFile) {
                _ = try? fh.seekToEnd()
                try? fh.write(contentsOf: data)
                try? fh.close()
            } else {
                try? data.write(to: auditFile, options: .atomic)
            }
        }
    }

    private func drainCommandsOnce() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: commandsDir, includingPropertiesForKeys: nil) else {
            return
        }
        if files.isEmpty { return }
        for url in files {
            if url.pathExtension.lowercased() != "json" { continue }
            defer { try? FileManager.default.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let typ = String(describing: obj["type"] ?? "")
            if typ == "stop" {
                // Embedded mode: keep service alive, only disable networking window.
                writeAudit("bridge_cmd_stop")
                operatorDisabled = true
                enabledUntil = 0
                if let data = try? JSONSerialization.data(withJSONObject: [
                    "enabled_until": 0,
                    "updated_at": Date().timeIntervalSince1970,
                ], options: []) {
                    try? data.write(to: settingsFile, options: .atomic)
                }
                tick()
                continue
            }
            if typ == "enable_until" {
                operatorDisabled = false
                if let v = obj["enabled_until"] as? Double {
                    enabledUntil = max(enabledUntil, v, Self.defaultEnabledUntil(now: Date().timeIntervalSince1970))
                } else if let v = obj["enabled_until"] as? Int {
                    enabledUntil = max(enabledUntil, Double(v), Self.defaultEnabledUntil(now: Date().timeIntervalSince1970))
                } else {
                    enabledUntil = max(enabledUntil, Self.defaultEnabledUntil(now: Date().timeIntervalSince1970))
                }
                writeAudit("bridge_cmd_enable_until")
                tick()
                continue
            }
            // Future: download_url / lan_discovery / etc.
            writeAudit("bridge_cmd_unknown")
        }
    }

    // -------------------- Fetch IPC (MVP: HTTPS GET only) --------------------

    private func drainRequestsOnce() {
        // Only process requests when enabled.
        if enabledUntil <= 0 || Date().timeIntervalSince1970 > enabledUntil {
            return
        }
        // Bounded concurrency: separate pools for web + AI, plus a global cap.
        if activeRequestTotal >= maxConcurrentTotal {
            return
        }

        guard let files = try? FileManager.default.contentsOfDirectory(at: requestsDir, includingPropertiesForKeys: nil) else {
            return
        }
        if files.isEmpty { return }

        for url in files {
            if activeRequestTotal >= maxConcurrentTotal { return }
            if url.pathExtension.lowercased() != "json" { continue }
            let name = url.lastPathComponent
            if !name.hasPrefix("req_") { continue }

            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            let typ = String(describing: obj["type"] ?? "")
            if typ == "fetch" {
                if activeWebFetchCount >= maxConcurrentWebFetch { continue }
                let rid = String(describing: obj["req_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let rawURL = String(describing: obj["url"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let method = String(describing: obj["method"] ?? "GET").uppercased()
                let timeoutSec = Double(obj["timeout_sec"] as? Double ?? 12.0)
                let maxBytes = Int(obj["max_bytes"] as? Int ?? 1_000_000)

                let headers: [String: String] = {
                    var out: [String: String] = [:]
                    if let rawHeaders = obj["headers"] as? [String: Any] {
                        for (k0, v0) in rawHeaders {
                            let k = k0.trimmingCharacters(in: .whitespacesAndNewlines)
                            if k.isEmpty || k.contains("\n") || k.contains("\r") { continue }
                            let v = String(describing: v0).trimmingCharacters(in: .whitespacesAndNewlines)
                            if v.isEmpty || v.contains("\n") || v.contains("\r") { continue }
                            out[k] = v
                        }
                    }
                    return out
                }()

                // Accept the request: remove the file so clients can retry with a new req_id if needed.
                try? FileManager.default.removeItem(at: url)

                activeWebFetchCount += 1
                Task { @MainActor in
                    await self.performFetch(reqId: rid, urlText: rawURL, method: method, headers: headers, timeoutSec: timeoutSec, maxBytes: maxBytes)
                }
                continue
            }

            if typ == "ai_generate" {
                if activeAIGenerateCount >= maxConcurrentAIGenerate { continue }
                let rid = String(describing: obj["req_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let modelId = String(describing: obj["model_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let allowDisabledModelLookup = (obj["allow_disabled_model_lookup"] as? Bool) ?? false
                let prompt = String(describing: obj["prompt"] ?? "")
                let maxTokens = Int(obj["max_tokens"] as? Int ?? 512)
                let temperature = Double(obj["temperature"] as? Double ?? 0.2)
                let topP = Double(obj["top_p"] as? Double ?? 0.95)
                let timeoutSec = Double(obj["timeout_sec"] as? Double ?? 60.0)

                // Accept the request: remove the file so clients can retry with a new req_id if needed.
                try? FileManager.default.removeItem(at: url)

                activeAIGenerateCount += 1
                Task { @MainActor in
                    await self.performAIGenerate(
                        reqId: rid,
                        modelId: modelId,
                        allowDisabledModelLookup: allowDisabledModelLookup,
                        prompt: prompt,
                        maxTokens: maxTokens,
                        temperature: temperature,
                        topP: topP,
                        timeoutSec: timeoutSec
                    )
                }
                continue
            }

            try? FileManager.default.removeItem(at: url)
        }
    }

    private func performFetch(reqId: String, urlText: String, method: String, headers: [String: String], timeoutSec: Double, maxBytes: Int) async {
        defer { activeWebFetchCount = max(0, activeWebFetchCount - 1) }

        func writeResp(ok: Bool, status: Int, finalURL: String, contentType: String, truncated: Bool, bytes: Int, text: String, error: String) {
            let resp: [String: Any] = [
                "type": "fetch_result",
                "req_id": reqId,
                "ok": ok,
                "status": status,
                "final_url": finalURL,
                "content_type": contentType,
                "truncated": truncated,
                "bytes": bytes,
                "text": text,
                "error": error,
                "updated_at": Date().timeIntervalSince1970,
            ]
            let tmp = responsesDir.appendingPathComponent(".resp_\(reqId).tmp")
            let out = responsesDir.appendingPathComponent("resp_\(reqId).json")
            if let data = try? JSONSerialization.data(withJSONObject: resp, options: []) {
                try? data.write(to: tmp, options: .atomic)
                try? FileManager.default.moveItem(at: tmp, to: out)
            }
        }

        let u0 = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: u0), let scheme = url.scheme?.lowercased() else {
            writeAudit("bridge_fetch_bad_url")
            writeResp(ok: false, status: 0, finalURL: "", contentType: "", truncated: false, bytes: 0, text: "", error: "bad_url")
            return
        }
        if scheme != "https" {
            writeAudit("bridge_fetch_reject_scheme")
            writeResp(ok: false, status: 0, finalURL: u0, contentType: "", truncated: false, bytes: 0, text: "", error: "reject_non_https")
            return
        }
        if method != "GET" {
            writeAudit("bridge_fetch_reject_method")
            writeResp(ok: false, status: 0, finalURL: u0, contentType: "", truncated: false, bytes: 0, text: "", error: "reject_method")
            return
        }

        writeAudit("bridge_fetch_start")

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = max(2.0, min(60.0, timeoutSec))
        for (k, v) in headers {
            let hk = k.trimmingCharacters(in: .whitespacesAndNewlines)
            if hk.isEmpty || hk.contains("\n") || hk.contains("\r") { continue }
            let hv = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if hv.isEmpty || hv.contains("\n") || hv.contains("\r") { continue }
            req.setValue(hv, forHTTPHeaderField: hk)
        }
        if req.value(forHTTPHeaderField: "User-Agent") == nil {
            req.setValue("RELFlowHubBridge/1.0", forHTTPHeaderField: "User-Agent")
        }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let http = resp as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            let ct = (http?.value(forHTTPHeaderField: "Content-Type") ?? "")
            let finalURL = resp.url?.absoluteString ?? u0

            let limited: Data
            let truncated: Bool
            if data.count > max(1, maxBytes) {
                limited = data.prefix(max(1, maxBytes))
                truncated = true
            } else {
                limited = data
                truncated = false
            }

            let text = String(data: limited, encoding: .utf8) ?? String(decoding: limited, as: UTF8.self)
            writeResp(ok: (status >= 200 && status < 300), status: status, finalURL: finalURL, contentType: ct, truncated: truncated, bytes: data.count, text: text, error: "")
            writeAudit("bridge_fetch_done")
        } catch {
            writeResp(ok: false, status: 0, finalURL: u0, contentType: "", truncated: false, bytes: 0, text: "", error: "fetch_failed:\(String(describing: error))")
            writeAudit("bridge_fetch_failed")
        }
    }

    // -------------------- Remote AI (OpenAI-compatible) --------------------

    private func performAIGenerate(
        reqId: String,
        modelId: String,
        allowDisabledModelLookup: Bool,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        timeoutSec: Double
    ) async {
        defer { activeAIGenerateCount = max(0, activeAIGenerateCount - 1) }

        func writeResp(ok: Bool, status: Int, text: String, error: String, usage: [String: Any] = [:]) {
            var resp: [String: Any] = [
                "type": "ai_generate_result",
                "req_id": reqId,
                "ok": ok,
                "status": status,
                "text": text,
                "error": error,
                "updated_at": Date().timeIntervalSince1970,
            ]
            if !usage.isEmpty {
                resp["usage"] = usage
            }
            let tmp = responsesDir.appendingPathComponent(".resp_\(reqId).tmp")
            let out = responsesDir.appendingPathComponent("resp_\(reqId).json")
            if let data = try? JSONSerialization.data(withJSONObject: resp, options: []) {
                try? data.write(to: tmp, options: .atomic)
                try? FileManager.default.moveItem(at: tmp, to: out)
            }
        }

        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else {
            writeResp(ok: false, status: 0, text: "", error: "bad_req_id")
            return
        }
        guard !modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            writeResp(ok: false, status: 0, text: "", error: "missing_model_id")
            return
        }

        let result = await RemoteModelTrialRunner.generate(
            modelId: modelId,
            allowDisabledModelLookup: allowDisabledModelLookup,
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            timeoutSec: timeoutSec
        )
        writeResp(
            ok: result.ok,
            status: result.status,
            text: result.text,
            error: result.error,
            usage: result.usage
        )
    }
}
