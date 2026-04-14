import Foundation
import RELFlowHubCore

@MainActor
enum RemoteModelTrialRunner {
    struct TrialResult {
        var ok: Bool
        var status: Int
        var text: String
        var error: String
        var usage: [String: Any]
    }

    static var providerCallOverride: ((
        RemoteModelEntry,
        String,
        Int,
        Double,
        Double,
        Double
    ) async -> TrialResult)? = nil

    static var httpDataOverride: ((URLRequest) async throws -> (Data, HTTPURLResponse))? = nil

    static func generate(
        modelId: String,
        allowDisabledModelLookup: Bool = false,
        prompt: String,
        maxTokens: Int = 24,
        temperature: Double = 0.0,
        topP: Double = 1.0,
        timeoutSec: Double = 20.0
    ) async -> TrialResult {
        let rid = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else {
            return TrialResult(ok: false, status: 0, text: "", error: "missing_model_id", usage: [:])
        }

        let allCandidates = allowDisabledModelLookup
            ? RemoteModelStorage.load().models
            : RemoteModelStorage.exportableEnabledModels()
        guard let remote = allCandidates.first(where: { $0.id == rid }) else {
            return TrialResult(ok: false, status: 0, text: "", error: "remote_model_not_found", usage: [:])
        }

        let backend = remote.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let upstream = upstreamKey(for: remote)
        let baseURL = baseURLKey(remote.baseURL)

        var candidates: [RemoteModelEntry] = [remote]
        if !allowDisabledModelLookup && !backend.isEmpty && !upstream.isEmpty {
            for candidate in allCandidates {
                if candidate.id == remote.id { continue }
                if candidate.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != backend { continue }
                if upstreamKey(for: candidate) != upstream { continue }
                if baseURLKey(candidate.baseURL) != baseURL { continue }
                candidates.append(candidate)
            }
        }
        if candidates.count > 1 {
            let head = candidates[0]
            let tail = candidates.dropFirst().sorted { $0.id.lowercased() < $1.id.lowercased() }
            candidates = [head] + tail
        }

        var lastResult: TrialResult?
        for (index, candidate) in candidates.enumerated() {
            let apiKey = (candidate.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if apiKey.isEmpty {
                continue
            }
            let result = await callProvider(
                remote: candidate,
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                timeoutSec: timeoutSec
            )
            lastResult = result
            if result.ok {
                return result
            }
            let isLastCandidate = index >= candidates.count - 1
            if !isLastCandidate && isQuotaOrRateLimit(status: result.status, error: result.error) {
                continue
            }
            break
        }

        return lastResult ?? TrialResult(ok: false, status: 0, text: "", error: "api_key_missing", usage: [:])
    }

    static func providerModelId(for remote: RemoteModelEntry) -> String {
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

    private static func upstreamKey(for model: RemoteModelEntry) -> String {
        let raw = (model.upstreamModelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw.isEmpty ? model.id : raw).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func baseURLKey(_ raw: String?) -> String {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "" }
        return value.lowercased()
    }

    private static func isQuotaOrRateLimit(status: Int, error: String) -> Bool {
        if status == 429 || status == 402 {
            return true
        }
        let normalized = error.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("quota") || normalized.contains("insufficient") {
            return true
        }
        if normalized.contains("rate limit") || normalized.contains("too many requests") {
            return true
        }
        return normalized.contains("exceeded") && normalized.contains("limit")
    }

    static func resolvedOpenAIWireAPI(for remote: RemoteModelEntry) -> RemoteProviderWireAPI {
        if let explicit = RemoteProviderEndpoints.normalizedWireAPI(remote.wireAPI) {
            return explicit
        }
        if let inferred = CodexProviderImportResolver.inferredOpenAIWireAPI(
            backend: remote.backend,
            baseURL: remote.baseURL
        ) {
            return inferred
        }
        return RemoteProviderEndpoints.resolvedOpenAIWireAPI(remote.wireAPI, backend: remote.backend)
    }

    private static func send(_ req: URLRequest) async throws -> (Data, Int) {
        if let httpDataOverride {
            let (data, response) = try await httpDataOverride(req)
            return (data, response.statusCode)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private static func providerErrorMessage(from obj: [String: Any]) -> String? {
        if let err = obj["error"] as? [String: Any] {
            let message = String(describing: err["message"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let code = String(describing: err["code"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty && !code.isEmpty && !message.lowercased().contains(code.lowercased()) {
                return "\(message) [\(code)]"
            }
            if !message.isEmpty { return message }
            if !code.isEmpty { return code }
        }
        let message = String(describing: obj["message"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? nil : message
    }

    private static func rawResponseText(_ data: Data) -> String {
        String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func jsonObject(from data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func failureResult(status: Int, fallbackText: String, object: [String: Any]? = nil) -> TrialResult {
        if let object, let error = providerErrorMessage(from: object), !error.isEmpty {
            return TrialResult(ok: false, status: status, text: "", error: error, usage: [:])
        }
        let trimmed = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        return TrialResult(
            ok: false,
            status: status,
            text: "",
            error: trimmed.isEmpty ? "http_\(status)" : trimmed,
            usage: [:]
        )
    }

    private static func parseResponsesText(from obj: [String: Any]) -> String {
        if let text = obj["output_text"] as? String {
            return text
        }

        var parts: [String] = []
        if let output = obj["output"] as? [[String: Any]] {
            for item in output {
                if let text = item["text"] as? String, !text.isEmpty {
                    parts.append(text)
                }
                if let content = item["content"] as? [[String: Any]] {
                    for part in content {
                        if let text = part["text"] as? String, !text.isEmpty {
                            parts.append(text)
                            continue
                        }
                        if let textObject = part["text"] as? [String: Any],
                           let value = textObject["value"] as? String,
                           !value.isEmpty {
                            parts.append(value)
                            continue
                        }
                        if let outputText = part["output_text"] as? String, !outputText.isEmpty {
                            parts.append(outputText)
                        }
                    }
                }
            }
        }
        return parts.joined()
    }

    private static func parseResponsesUsage(from obj: [String: Any]) -> [String: Any] {
        guard let rawUsage = obj["usage"] as? [String: Any] else { return [:] }
        var usage: [String: Any] = [:]
        if let promptTokens = rawUsage["input_tokens"] ?? rawUsage["prompt_tokens"] {
            usage["prompt_tokens"] = promptTokens
        }
        if let completionTokens = rawUsage["output_tokens"] ?? rawUsage["completion_tokens"] {
            usage["completion_tokens"] = completionTokens
        }
        if let totalTokens = rawUsage["total_tokens"] {
            usage["total_tokens"] = totalTokens
        }
        return usage
    }

    private static func callProvider(
        remote: RemoteModelEntry,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        timeoutSec: Double
    ) async -> TrialResult {
        if let providerCallOverride {
            return await providerCallOverride(remote, prompt, maxTokens, temperature, topP, timeoutSec)
        }

        switch RemoteProviderEndpoints.canonicalBackend(remote.backend) {
        case "anthropic":
            return await performAnthropic(
                remote: remote,
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                timeoutSec: timeoutSec
            )
        case "gemini":
            return await performGemini(
                remote: remote,
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                timeoutSec: timeoutSec
            )
        case "remote_catalog":
            var normalizedRemote = remote
            let baseURL = (normalizedRemote.baseURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if baseURL.isEmpty {
                normalizedRemote.baseURL = RemoteProviderEndpoints.remoteCatalogBaseURLString
            }
            return await performOpenAICompatible(
                remote: normalizedRemote,
                modelId: providerModelId(for: normalizedRemote),
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                timeoutSec: timeoutSec
            )
        default:
            return await performOpenAICompatible(
                remote: remote,
                modelId: providerModelId(for: remote),
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                timeoutSec: timeoutSec
            )
        }
    }

    private static func performOpenAICompatible(
        remote: RemoteModelEntry,
        modelId: String,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        timeoutSec: Double
    ) async -> TrialResult {
        switch resolvedOpenAIWireAPI(for: remote) {
        case .responses:
            return await performOpenAIResponses(
                remote: remote,
                modelId: modelId,
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                timeoutSec: timeoutSec
            )
        case .chatCompletions:
            return await performOpenAIChatCompletions(
                remote: remote,
                modelId: modelId,
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                timeoutSec: timeoutSec
            )
        }
    }

    private static func performOpenAIChatCompletions(
        remote: RemoteModelEntry,
        modelId: String,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        timeoutSec: Double
    ) async -> TrialResult {
        guard let url = RemoteProviderEndpoints.openAIChatCompletionsURL(baseURL: remote.baseURL, backend: remote.backend) else {
            return TrialResult(ok: false, status: 0, text: "", error: "base_url_invalid", usage: [:])
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = max(5.0, min(120.0, timeoutSec))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = remote.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("RELFlowHub/1.0", forHTTPHeaderField: "User-Agent")

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
            return TrialResult(ok: false, status: 0, text: "", error: "encode_failed", usage: [:])
        }
        req.httpBody = data

        do {
            let (data, status) = try await send(req)
            let rawText = rawResponseText(data)
            guard let obj = jsonObject(from: data) else {
                if status >= 200 && status < 300 {
                    return TrialResult(ok: false, status: status, text: "", error: "bad_json:\(rawText)", usage: [:])
                }
                return failureResult(status: status, fallbackText: rawText)
            }
            if status < 200 || status >= 300 {
                return failureResult(status: status, fallbackText: rawText, object: obj)
            }

            var text = ""
            if let choices = obj["choices"] as? [[String: Any]], let first = choices.first {
                if let message = first["message"] as? [String: Any], let content = message["content"] as? String {
                    text = content
                } else if let content = first["text"] as? String {
                    text = content
                }
            }

            let usage = (obj["usage"] as? [String: Any]) ?? [:]
            return TrialResult(ok: true, status: status, text: text, error: "", usage: usage)
        } catch {
            return TrialResult(ok: false, status: 0, text: "", error: "fetch_failed:\(String(describing: error))", usage: [:])
        }
    }

    private static func performOpenAIResponses(
        remote: RemoteModelEntry,
        modelId: String,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        timeoutSec: Double
    ) async -> TrialResult {
        guard let url = RemoteProviderEndpoints.openAIResponsesURL(baseURL: remote.baseURL, backend: remote.backend) else {
            return TrialResult(ok: false, status: 0, text: "", error: "base_url_invalid", usage: [:])
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = max(5.0, min(120.0, timeoutSec))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = remote.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("RELFlowHub/1.0", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "model": modelId,
            "input": prompt,
            "temperature": temperature,
            "top_p": topP,
            "max_output_tokens": max(1, min(8192, maxTokens)),
            "stream": false,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            return TrialResult(ok: false, status: 0, text: "", error: "encode_failed", usage: [:])
        }
        req.httpBody = data

        do {
            let (data, status) = try await send(req)
            let rawText = rawResponseText(data)
            guard let obj = jsonObject(from: data) else {
                if status >= 200 && status < 300 {
                    return TrialResult(ok: false, status: status, text: "", error: "bad_json:\(rawText)", usage: [:])
                }
                return failureResult(status: status, fallbackText: rawText)
            }
            if status < 200 || status >= 300 {
                return failureResult(status: status, fallbackText: rawText, object: obj)
            }

            return TrialResult(
                ok: true,
                status: status,
                text: parseResponsesText(from: obj),
                error: "",
                usage: parseResponsesUsage(from: obj)
            )
        } catch {
            return TrialResult(ok: false, status: 0, text: "", error: "fetch_failed:\(String(describing: error))", usage: [:])
        }
    }

    private static func performAnthropic(
        remote: RemoteModelEntry,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        timeoutSec: Double
    ) async -> TrialResult {
        guard let url = RemoteProviderEndpoints.anthropicMessagesURL(baseURL: remote.baseURL) else {
            return TrialResult(ok: false, status: 0, text: "", error: "base_url_invalid", usage: [:])
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = max(5.0, min(120.0, timeoutSec))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = remote.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            req.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("RELFlowHub/1.0", forHTTPHeaderField: "User-Agent")

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
            return TrialResult(ok: false, status: 0, text: "", error: "encode_failed", usage: [:])
        }
        req.httpBody = data

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0

            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let text = String(data: data, encoding: .utf8) ?? ""
                return TrialResult(ok: false, status: status, text: "", error: "bad_json:\(text)", usage: [:])
            }

            if let err = obj["error"] as? [String: Any],
               let message = err["message"] as? String {
                return TrialResult(ok: false, status: status, text: "", error: message, usage: [:])
            }

            var text = ""
            if let content = obj["content"] as? [[String: Any]] {
                let parts = content.compactMap { $0["text"] as? String }
                text = parts.joined()
            }

            var usage: [String: Any] = [:]
            if let rawUsage = obj["usage"] as? [String: Any] {
                if let promptTokens = rawUsage["input_tokens"] { usage["prompt_tokens"] = promptTokens }
                if let completionTokens = rawUsage["output_tokens"] { usage["completion_tokens"] = completionTokens }
            }

            let ok = status >= 200 && status < 300
            return TrialResult(ok: ok, status: status, text: text, error: ok ? "" : "http_\(status)", usage: usage)
        } catch {
            return TrialResult(ok: false, status: 0, text: "", error: "fetch_failed:\(String(describing: error))", usage: [:])
        }
    }

    private static func performGemini(
        remote: RemoteModelEntry,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        timeoutSec: Double
    ) async -> TrialResult {
        guard let url = RemoteProviderEndpoints.geminiGenerateURL(
            baseURL: remote.baseURL,
            modelId: providerModelId(for: remote),
            apiKey: remote.apiKey
        ) else {
            return TrialResult(ok: false, status: 0, text: "", error: "base_url_invalid", usage: [:])
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = max(5.0, min(120.0, timeoutSec))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("RELFlowHub/1.0", forHTTPHeaderField: "User-Agent")

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
            return TrialResult(ok: false, status: 0, text: "", error: "encode_failed", usage: [:])
        }
        req.httpBody = data

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0

            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let text = String(data: data, encoding: .utf8) ?? ""
                return TrialResult(ok: false, status: status, text: "", error: "bad_json:\(text)", usage: [:])
            }

            if let err = obj["error"] as? [String: Any],
               let message = err["message"] as? String {
                return TrialResult(ok: false, status: status, text: "", error: message, usage: [:])
            }

            var text = ""
            if let candidates = obj["candidates"] as? [[String: Any]], let first = candidates.first {
                if let content = first["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]] {
                    text = parts.compactMap { $0["text"] as? String }.joined()
                }
            }

            var usage: [String: Any] = [:]
            if let rawUsage = obj["usageMetadata"] as? [String: Any] {
                if let promptTokens = rawUsage["promptTokenCount"] { usage["prompt_tokens"] = promptTokens }
                if let completionTokens = rawUsage["candidatesTokenCount"] { usage["completion_tokens"] = completionTokens }
            }

            let ok = status >= 200 && status < 300
            return TrialResult(ok: ok, status: status, text: text, error: ok ? "" : "http_\(status)", usage: usage)
        } catch {
            return TrialResult(ok: false, status: 0, text: "", error: "fetch_failed:\(String(describing: error))", usage: [:])
        }
    }
}
