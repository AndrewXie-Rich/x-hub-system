import Foundation
import RELFlowHubCore

// Embedded networking helper running inside the Hub app.
// It preserves the same filesystem IPC contract as RELFlowHubBridge.

@MainActor
final class EmbeddedBridgeRunner {
    private var heartbeatTimer: Timer?
    private var commandTimer: Timer?
    private var enabledUntil: Double = 0
    private let startedAt = Date().timeIntervalSince1970

    // Shared container (App Group). This is the contract with the core Hub.
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
        // Prefer App Group when available (properly signed builds).
        //
        // For ad-hoc/sandbox builds where App Group isn't available, keep Bridge IPC inside
        // the Hub base directory (typically the app container). Some sandbox profiles cannot
        // write to global temp paths like /private/tmp, which would make paid/web features
        // fail with `bridge_unavailable` even though the Hub app is running.
        baseDir = SharedPaths.appGroupDirectory() ?? SharedPaths.ensureHubDirectory()
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
        // Default: enabled for 0 seconds until user turns it on from core Hub.
        enabledUntil = 0
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
        let rem = Int(max(0, enabledUntil - Date().timeIntervalSince1970))
        return "on (\(rem)s left)"
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
        // Load settings (enabled_until).
        if let data = try? Data(contentsOf: settingsFile),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let v = obj["enabled_until"] as? Double {
                enabledUntil = v
            } else if let v = obj["enabled_until"] as? Int {
                enabledUntil = Double(v)
            }
        }

        // In embedded mode, expiration only disables networking for requests.
        if enabledUntil > 0 && Date().timeIntervalSince1970 > enabledUntil {
            writeAudit("bridge_auto_disable")
            enabledUntil = 0
            if let data = try? JSONSerialization.data(withJSONObject: [
                "enabled_until": 0,
                "updated_at": Date().timeIntervalSince1970,
            ], options: []) {
                try? data.write(to: settingsFile, options: .atomic)
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
                try? fh.seekToEnd()
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
                if let v = obj["enabled_until"] as? Double {
                    enabledUntil = v
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

        let allEnabled = RemoteModelStorage.exportableEnabledModels()
        let remote = allEnabled.first { $0.id == modelId }
        guard let rm = remote else {
            writeResp(ok: false, status: 0, text: "", error: "remote_model_not_found")
            return
        }

        func upstreamKey(_ m: RemoteModelEntry) -> String {
            let raw = (m.upstreamModelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw.isEmpty ? m.id : raw).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        func baseURLKey(_ raw: String?) -> String {
            let s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { return "" }
            return s.lowercased()
        }

        func isQuotaOrRateLimit(status: Int, error: String) -> Bool {
            if status == 429 || status == 402 {
                return true
            }
            let e = error.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if e.contains("quota") { return true }
            if e.contains("insufficient") { return true }
            if e.contains("rate limit") { return true }
            if e.contains("too many requests") { return true }
            if e.contains("exceeded") && e.contains("limit") { return true }
            return false
        }

        let backend = rm.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ukey = upstreamKey(rm)
        let bkey = baseURLKey(rm.baseURL)

        var candidates: [RemoteModelEntry] = [rm]
        // Failover candidates: same upstream + backend (+ baseURL), different key ref.
        if !ukey.isEmpty && !backend.isEmpty {
            for m in allEnabled {
                if m.id == rm.id { continue }
                if m.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != backend { continue }
                if upstreamKey(m) != ukey { continue }
                if baseURLKey(m.baseURL) != bkey { continue }
                candidates.append(m)
            }
        }
        if candidates.count > 1 {
            let head = candidates[0]
            let tail = candidates.dropFirst().sorted { $0.id.lowercased() < $1.id.lowercased() }
            candidates = [head] + tail
        }

        func callProvider(_ remote: RemoteModelEntry) async -> (ok: Bool, status: Int, text: String, error: String, usage: [String: Any]) {
            switch RemoteProviderEndpoints.canonicalBackend(backend) {
            case "anthropic":
                return await performAnthropic(remote: remote, prompt: prompt, maxTokens: maxTokens, temperature: temperature, topP: topP, timeoutSec: timeoutSec)
            case "gemini":
                return await performGemini(remote: remote, prompt: prompt, maxTokens: maxTokens, temperature: temperature, topP: topP, timeoutSec: timeoutSec)
            case "remote_catalog":
                // Prefer an OpenAI-compatible request shape for the remote catalog and send the provider model id upstream.
                let upstreamModelId = providerModelId(for: remote)
                var remote2 = remote
                let base = (remote2.baseURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if base.isEmpty {
                    remote2.baseURL = RemoteProviderEndpoints.remoteCatalogBaseURLString
                }
                return await performOpenAICompatible(remote: remote2, modelId: upstreamModelId, prompt: prompt, maxTokens: maxTokens, temperature: temperature, topP: topP, timeoutSec: timeoutSec)
            default:
                return await performOpenAICompatible(remote: remote, modelId: providerModelId(for: remote), prompt: prompt, maxTokens: maxTokens, temperature: temperature, topP: topP, timeoutSec: timeoutSec)
            }
        }

        var last: (ok: Bool, status: Int, text: String, error: String, usage: [String: Any])? = nil
        for (idx, cand) in candidates.enumerated() {
            let apiKey = (cand.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if apiKey.isEmpty {
                continue
            }
            let res = await callProvider(cand)
            last = res
            if res.ok {
                writeResp(ok: res.ok, status: res.status, text: res.text, error: res.error, usage: res.usage)
                return
            }
            let isLast = (idx >= candidates.count - 1)
            if !isLast, isQuotaOrRateLimit(status: res.status, error: res.error) {
                continue
            }
            break
        }

        if let last {
            writeResp(ok: last.ok, status: last.status, text: last.text, error: last.error, usage: last.usage)
        } else {
            writeResp(ok: false, status: 0, text: "", error: "api_key_missing")
        }
    }

    private func providerModelId(for remote: RemoteModelEntry) -> String {
        let raw = (remote.upstreamModelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let model = raw.isEmpty ? remote.id.trimmingCharacters(in: .whitespacesAndNewlines) : raw
        let backend = RemoteProviderEndpoints.canonicalBackend(remote.backend)
        if backend == "gemini" || backend == "remote_catalog" {
            return RemoteProviderEndpoints.stripModelRef(model)
        }
        if model.hasPrefix("models/") {
            return RemoteProviderEndpoints.stripModelRef(model)
        }
        return model
    }

    private func performOpenAICompatible(
        remote: RemoteModelEntry,
        modelId: String,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        timeoutSec: Double
    ) async -> (ok: Bool, status: Int, text: String, error: String, usage: [String: Any]) {
        guard let url = RemoteProviderEndpoints.openAIChatCompletionsURL(baseURL: remote.baseURL, backend: remote.backend) else {
            return (false, 0, "", "base_url_invalid", [:])
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = max(5.0, min(120.0, timeoutSec))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = remote.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("RELFlowHubBridge/1.0", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "user", "content": prompt],
            ],
            "temperature": temperature,
            "top_p": topP,
            "max_tokens": max(1, min(8192, maxTokens)),
            "stream": false,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            return (false, 0, "", "encode_failed", [:])
        }
        req.httpBody = data

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let http = resp as? HTTPURLResponse
            let status = http?.statusCode ?? 0

            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let text = String(data: data, encoding: .utf8) ?? ""
                return (false, status, "", "bad_json:\(text)", [:])
            }

            if let err = obj["error"] as? [String: Any],
               let msg = err["message"] as? String {
                return (false, status, "", msg, [:])
            }

            var textOut = ""
            if let choices = obj["choices"] as? [[String: Any]], let first = choices.first {
                if let msg = first["message"] as? [String: Any], let content = msg["content"] as? String {
                    textOut = content
                } else if let content = first["text"] as? String {
                    textOut = content
                }
            }

            var usage: [String: Any] = [:]
            if let u = obj["usage"] as? [String: Any] {
                usage = u
            }

            let ok = (status >= 200 && status < 300)
            return (ok, status, textOut, ok ? "" : "http_\(status)", usage)
        } catch {
            return (false, 0, "", "fetch_failed:\(String(describing: error))", [:])
        }
    }

    private func performAnthropic(
        remote: RemoteModelEntry,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        timeoutSec: Double
    ) async -> (ok: Bool, status: Int, text: String, error: String, usage: [String: Any]) {
        guard let url = RemoteProviderEndpoints.anthropicMessagesURL(baseURL: remote.baseURL) else {
            return (false, 0, "", "base_url_invalid", [:])
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = max(5.0, min(120.0, timeoutSec))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = remote.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            req.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("RELFlowHubBridge/1.0", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "model": providerModelId(for: remote),
            "max_tokens": max(1, min(8192, maxTokens)),
            "temperature": temperature,
            "top_p": topP,
            "messages": [
                ["role": "user", "content": prompt],
            ],
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            return (false, 0, "", "encode_failed", [:])
        }
        req.httpBody = data

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let http = resp as? HTTPURLResponse
            let status = http?.statusCode ?? 0

            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let text = String(data: data, encoding: .utf8) ?? ""
                return (false, status, "", "bad_json:\(text)", [:])
            }

            if let err = obj["error"] as? [String: Any],
               let msg = err["message"] as? String {
                return (false, status, "", msg, [:])
            }

            var textOut = ""
            if let content = obj["content"] as? [[String: Any]] {
                let parts = content.compactMap { part -> String? in
                    if let t = part["text"] as? String { return t }
                    return nil
                }
                textOut = parts.joined()
            }

            var usage: [String: Any] = [:]
            if let u = obj["usage"] as? [String: Any] {
                if let p = u["input_tokens"] { usage["prompt_tokens"] = p }
                if let c = u["output_tokens"] { usage["completion_tokens"] = c }
            }

            let ok = (status >= 200 && status < 300)
            return (ok, status, textOut, ok ? "" : "http_\(status)", usage)
        } catch {
            return (false, 0, "", "fetch_failed:\(String(describing: error))", [:])
        }
    }

    private func performGemini(
        remote: RemoteModelEntry,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        timeoutSec: Double
    ) async -> (ok: Bool, status: Int, text: String, error: String, usage: [String: Any]) {
        guard let url = RemoteProviderEndpoints.geminiGenerateURL(
            baseURL: remote.baseURL,
            modelId: providerModelId(for: remote),
            apiKey: remote.apiKey
        ) else {
            return (false, 0, "", "base_url_invalid", [:])
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = max(5.0, min(120.0, timeoutSec))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("RELFlowHubBridge/1.0", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": prompt],
                    ],
                ],
            ],
            "generationConfig": [
                "temperature": temperature,
                "topP": topP,
                "maxOutputTokens": max(1, min(8192, maxTokens)),
            ],
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            return (false, 0, "", "encode_failed", [:])
        }
        req.httpBody = data

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let http = resp as? HTTPURLResponse
            let status = http?.statusCode ?? 0

            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let text = String(data: data, encoding: .utf8) ?? ""
                return (false, status, "", "bad_json:\(text)", [:])
            }

            if let err = obj["error"] as? [String: Any],
               let msg = err["message"] as? String {
                return (false, status, "", msg, [:])
            }

            var textOut = ""
            if let candidates = obj["candidates"] as? [[String: Any]], let first = candidates.first {
                if let content = first["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]] {
                    let texts = parts.compactMap { $0["text"] as? String }
                    textOut = texts.joined()
                }
            }

            var usage: [String: Any] = [:]
            if let u = obj["usageMetadata"] as? [String: Any] {
                if let p = u["promptTokenCount"] { usage["prompt_tokens"] = p }
                if let c = u["candidatesTokenCount"] { usage["completion_tokens"] = c }
            }

            let ok = (status >= 200 && status < 300)
            return (ok, status, textOut, ok ? "" : "http_\(status)", usage)
        } catch {
            return (false, 0, "", "fetch_failed:\(String(describing: error))", [:])
        }
    }
}
