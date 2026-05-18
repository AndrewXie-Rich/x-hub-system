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
        var accountKey: String = ""
        var provider: String = ""
        var modelID: String = ""
        var latencyMs: Int64 = 0
        var occurredAtMs: Int64 = 0
    }

    struct ProviderKeyExecutionOverride: Sendable, Equatable {
        var accountKey: String
        var provider: String
        var apiKey: String
        var baseURL: String
        var proxyURL: String
        var authType: String
        var refreshToken: String = ""
        var accountId: String = ""
        var oauthSourceKey: String = ""
        var authIndex: Int = 0
        var sourceType: String = ""
        var sourceRef: String = ""
        var customHeaders: [String: String]
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
    private static var providerPoolCursors: [String: Int] = [:]

    static func generate(
        modelId: String,
        allowDisabledModelLookup: Bool = false,
        prompt: String,
        maxTokens: Int = 24,
        temperature: Double = 0.0,
        topP: Double = 1.0,
        timeoutSec: Double = 20.0,
        providerKeyOverride: ProviderKeyExecutionOverride? = nil
    ) async -> TrialResult {
        let rid = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else {
            return TrialResult(ok: false, status: 0, text: "", error: "missing_model_id", usage: [:])
        }

        let resolvedOverride = resolvedProviderKeyOverride(providerKeyOverride)
        let allCandidates = (allowDisabledModelLookup || resolvedOverride != nil)
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
        candidateLoop: for (candidateIndex, candidate) in candidates.enumerated() {
            let overrideOptions = providerKeyOverrideOptions(
                for: candidate,
                resolvedOverride: resolvedOverride
            )
            for (overrideIndex, effectiveOverride) in overrideOptions.enumerated() {
                let apiKey = overrideAPIKey(effectiveOverride, fallback: candidate.apiKey)
                if apiKey.isEmpty {
                    continue
                }
                let startedAtMs = currentTimestampMs()
                let result = await callProvider(
                    remote: candidate,
                    prompt: prompt,
                    maxTokens: maxTokens,
                    temperature: temperature,
                    topP: topP,
                    timeoutSec: timeoutSec,
                    providerKeyOverride: effectiveOverride
                )
                let finalized = finalizedResult(
                    result,
                    remote: candidate,
                    providerKeyOverride: effectiveOverride,
                    startedAtMs: startedAtMs
                )
                _ = RemoteProviderKeyRuntimeFeedbackRecorder.recordResult(finalized)
                lastResult = finalized
                if finalized.ok {
                    return finalized
                }

                let retryable = shouldTryNextCandidate(status: finalized.status, error: finalized.error)
                if retryable {
                    if overrideIndex < overrideOptions.count - 1 {
                        continue
                    }
                    if candidateIndex < candidates.count - 1 {
                        continue candidateLoop
                    }
                }
                break candidateLoop
            }
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
        if backend == "openai" {
            return RemoteProviderEndpoints.normalizedOpenAIModelID(model)
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

    private static func resolvedProviderKeyOverride(
        _ override: ProviderKeyExecutionOverride?
    ) -> ProviderKeyExecutionOverride? {
        guard var override else { return nil }
        override.accountKey = override.accountKey.trimmingCharacters(in: .whitespacesAndNewlines)
        override.provider = override.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        override.apiKey = override.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        override.baseURL = override.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        override.proxyURL = override.proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        override.authType = override.authType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        override.refreshToken = override.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        override.accountId = override.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        override.oauthSourceKey = override.oauthSourceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        override.sourceType = override.sourceType.trimmingCharacters(in: .whitespacesAndNewlines)
        override.sourceRef = override.sourceRef.trimmingCharacters(in: .whitespacesAndNewlines)

        if override.apiKey.isEmpty, !override.accountKey.isEmpty,
           let resolved = ProviderKeyStorage.loadResolvedCredential(accountKey: override.accountKey) {
            override.provider = override.provider.isEmpty ? resolved.provider : override.provider
            override.apiKey = resolved.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            override.refreshToken = override.refreshToken.isEmpty ? resolved.refreshToken : override.refreshToken
            override.baseURL = override.baseURL.isEmpty ? resolved.baseURL : override.baseURL
            override.proxyURL = override.proxyURL.isEmpty ? resolved.proxyURL : override.proxyURL
            override.authType = override.authType.isEmpty ? resolved.authType.lowercased() : override.authType
            override.accountId = override.accountId.isEmpty ? resolved.accountId : override.accountId
            override.oauthSourceKey = override.oauthSourceKey.isEmpty ? resolved.oauthSourceKey : override.oauthSourceKey
            override.authIndex = override.authIndex == 0 ? resolved.authIndex : override.authIndex
            override.sourceType = override.sourceType.isEmpty ? resolved.sourceType : override.sourceType
            override.sourceRef = override.sourceRef.isEmpty ? resolved.sourceRef : override.sourceRef
            if override.customHeaders.isEmpty {
                override.customHeaders = resolved.customHeaders
            }
        }

        if override.apiKey.isEmpty {
            return nil
        }
        return override
    }

    private static func providerKeyOverrideOptions(
        for remote: RemoteModelEntry,
        resolvedOverride: ProviderKeyExecutionOverride?
    ) -> [ProviderKeyExecutionOverride?] {
        if let resolvedOverride {
            return [resolvedOverride]
        }
        let inferred = inferredProviderKeyOverrides(for: remote)
        return inferred.isEmpty ? [nil] : inferred.map { Optional($0) }
    }

    private static func inferredProviderKeyOverrides(
        for remote: RemoteModelEntry
    ) -> [ProviderKeyExecutionOverride] {
        let accountKey = remote.apiKeyRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !accountKey.isEmpty,
           let resolved = ProviderKeyStorage.loadResolvedCredential(accountKey: accountKey) {
            return providerKeyExecutionOverrides(from: orderedPooledCredentials(preferred: resolved, for: remote))
        }

        let apiKey = remote.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !apiKey.isEmpty,
              let resolved = ProviderKeyStorage.loadResolvedCredential(
                apiKey: apiKey,
                provider: remote.backend,
                baseURL: remote.baseURL
              ) else {
            return []
        }
        return providerKeyExecutionOverrides(from: orderedPooledCredentials(preferred: resolved, for: remote))
    }

    private static func orderedPooledCredentials(
        preferred: ProviderKeyResolvedCredential,
        for remote: RemoteModelEntry
    ) -> [ProviderKeyResolvedCredential] {
        let modelID = providerModelId(for: remote)
        guard !preferred.poolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let pool = ProviderKeyStorage.loadRoutableCredentialPool(
                provider: preferred.provider,
                poolID: preferred.poolID,
                modelID: modelID
              ) else {
            return [preferred]
        }
        let credentials = pool.credentials
        guard !credentials.isEmpty else { return [] }
        guard normalizedRoutingStrategy(pool.routingStrategy) == "round-robin" else {
            return credentials
        }

        let cursorKey = "\(pool.poolID)::\(modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        let start = max(0, providerPoolCursors[cursorKey] ?? 0) % credentials.count
        providerPoolCursors[cursorKey] = start + 1
        var ordered = Array(credentials[start..<credentials.count])
        if start > 0 {
            ordered.append(contentsOf: credentials[0..<start])
        }
        return ordered
    }

    private static func normalizedRoutingStrategy(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }

    private static func providerKeyExecutionOverrides(
        from credentials: [ProviderKeyResolvedCredential]
    ) -> [ProviderKeyExecutionOverride] {
        credentials.compactMap(providerKeyExecutionOverride(from:))
    }

    private static func providerKeyExecutionOverride(
        from credential: ProviderKeyResolvedCredential
    ) -> ProviderKeyExecutionOverride? {
        resolvedProviderKeyOverride(
            ProviderKeyExecutionOverride(
                accountKey: credential.accountKey,
                provider: credential.provider,
                apiKey: credential.apiKey,
                baseURL: credential.baseURL,
                proxyURL: credential.proxyURL,
                authType: credential.authType,
                refreshToken: credential.refreshToken,
                accountId: credential.accountId,
                oauthSourceKey: credential.oauthSourceKey,
                authIndex: credential.authIndex,
                sourceType: credential.sourceType,
                sourceRef: credential.sourceRef,
                customHeaders: credential.customHeaders
            )
        )
    }

    private static func overrideAPIKey(
        _ override: ProviderKeyExecutionOverride?,
        fallback: String?
    ) -> String {
        let preferred = override?.apiKey.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !preferred.isEmpty {
            return preferred
        }
        return (fallback ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func effectiveBaseURL(
        remote: RemoteModelEntry,
        providerKeyOverride: ProviderKeyExecutionOverride?
    ) -> String? {
        let base = providerKeyOverride?.baseURL.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !base.isEmpty {
            return base
        }
        let proxy = providerKeyOverride?.proxyURL.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !proxy.isEmpty {
            return proxy
        }
        return remote.baseURL
    }

    private static func applyProviderKeyHeaders(
        _ request: inout URLRequest,
        providerKeyOverride: ProviderKeyExecutionOverride?
    ) {
        guard let providerKeyOverride else { return }
        for (headerKey, rawValue) in providerKeyOverride.customHeaders {
            let key = headerKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    private static func shouldTryNextCandidate(status: Int, error: String) -> Bool {
        if isQuotaOrRateLimit(status: status, error: error) {
            return true
        }

        let normalized = error.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if status == 401 || status == 403 {
            return true
        }
        if normalized.contains("scope")
            || normalized.contains("permissions")
            || normalized.contains("unauthorized")
            || normalized.contains("forbidden")
            || normalized.contains("authentication")
            || normalized.contains("api key")
            || normalized.contains("权限不足") {
            return true
        }

        return RemoteProviderKeyRuntimeFeedbackSupport.shouldTryNextCandidate(
            status: status,
            error: error
        )
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

    static func resolvedOpenAIWireAPI(
        for remote: RemoteModelEntry,
        providerKeyOverride: ProviderKeyExecutionOverride? = nil
    ) -> RemoteProviderWireAPI {
        if supportsOpenAIChatCompletionsCompatFallback(
            remote: remote,
            providerKeyOverride: providerKeyOverride
        ) {
            let explicit = RemoteProviderEndpoints.normalizedWireAPI(remote.wireAPI)
            if explicit == .responses {
                return .chatCompletions
            }
        }

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

    private static func isLikelyOpenAIOAuthAccessToken(
        _ rawToken: String,
        backend: String,
        baseURL: String?
    ) -> Bool {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return false }

        let canonicalBackend = RemoteProviderEndpoints.canonicalBackend(backend)
        guard canonicalBackend == "openai" || canonicalBackend == "openai_compatible" else {
            return false
        }

        if token.hasPrefix("sk-") || token.hasPrefix("rk-") {
            return false
        }

        let parts = token.split(separator: ".")
        guard parts.count == 3, token.hasPrefix("eyJ") else {
            return false
        }

        if let payload = decodedJWTPayload(token),
           isLikelyOpenAIOAuthPayload(payload) {
            return true
        }

        if let baseURL,
           let host = URL(string: baseURL)?.host?.lowercased(),
           !host.isEmpty {
            return host.contains("openai.com")
        }

        return true
    }

    private static func decodedJWTPayload(_ rawToken: String) -> [String: Any]? {
        let parts = rawToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func isLikelyOpenAIOAuthPayload(_ payload: [String: Any]) -> Bool {
        if let issuer = payload["iss"] as? String,
           issuer.lowercased().contains("openai.com") {
            return true
        }

        let audience: [String]
        if let list = payload["aud"] as? [String] {
            audience = list
        } else if let list = payload["aud"] as? [Any] {
            audience = list.compactMap { $0 as? String }
        } else if let string = payload["aud"] as? String {
            audience = [string]
        } else {
            audience = []
        }

        if audience.contains(where: { $0.lowercased().contains("api.openai.com") }) {
            return true
        }

        return payload.keys.contains { key in
            let normalized = key.lowercased()
            return normalized.contains("api.openai.com/auth")
                || normalized.contains("api.openai.com/profile")
        }
    }

    private static func supportsOpenAIChatCompletionsCompatFallback(
        remote: RemoteModelEntry,
        providerKeyOverride: ProviderKeyExecutionOverride?
    ) -> Bool {
        if let provider = providerKeyOverride?.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           provider == "codex" {
            return true
        }
        if let authType = providerKeyOverride?.authType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           authType == "oauth" {
            return true
        }

        let effectiveToken = overrideAPIKey(providerKeyOverride, fallback: remote.apiKey)
        let effectiveBaseURL = effectiveBaseURL(remote: remote, providerKeyOverride: providerKeyOverride)
        return isLikelyOpenAIOAuthAccessToken(
            effectiveToken,
            backend: remote.backend,
            baseURL: effectiveBaseURL
        )
    }

    private static func shouldFallbackFromResponsesToChatCompletions(
        result: TrialResult,
        remote: RemoteModelEntry,
        providerKeyOverride: ProviderKeyExecutionOverride?
    ) -> Bool {
        guard !result.ok else { return false }
        let supportsOAuthCompatFallback = supportsOpenAIChatCompletionsCompatFallback(
            remote: remote,
            providerKeyOverride: providerKeyOverride
        )
        let supportsThirdPartyCompatFallback = isThirdPartyOpenAICompatibleHost(
            backend: remote.backend,
            baseURL: effectiveBaseURL(remote: remote, providerKeyOverride: providerKeyOverride)
        )
        guard supportsOAuthCompatFallback || supportsThirdPartyCompatFallback else { return false }

        let normalizedError = result.error.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if supportsOAuthCompatFallback,
           (normalizedError.contains("api.responses.write") || normalizedError.contains("responses.write")) {
            return true
        }
        if supportsOAuthCompatFallback,
           (result.status == 401 || result.status == 403),
           normalizedError.contains("missing scopes") {
            return true
        }

        if supportsThirdPartyCompatFallback {
            if [404, 405, 408, 409, 410, 422, 429, 500, 501, 502, 503, 504].contains(result.status) {
                return true
            }

            switch hubClassifyModelTrialFailure(result.error) {
            case .timeout, .network, .unsupported, .config:
                return true
            default:
                break
            }
        }

        return false
    }

    private static func isThirdPartyOpenAICompatibleHost(
        backend: String,
        baseURL: String?
    ) -> Bool {
        let canonicalBackend = RemoteProviderEndpoints.canonicalBackend(backend)
        guard canonicalBackend == "openai_compatible" || canonicalBackend == "openai",
              let baseURL,
              let host = URL(string: baseURL)?.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !host.isEmpty else {
            return false
        }

        return !host.contains("openai.com") && !host.contains("chatgpt.com")
    }

    private static func send(_ req: URLRequest) async throws -> (Data, Int) {
        if let httpDataOverride {
            let (data, response) = try await httpDataOverride(req)
            return (data, response.statusCode)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private static func finalizedResult(
        _ result: TrialResult,
        remote: RemoteModelEntry,
        providerKeyOverride: ProviderKeyExecutionOverride?,
        startedAtMs: Int64
    ) -> TrialResult {
        var finalized = result
        let occurredAtMs = currentTimestampMs()
        finalized.accountKey = providerKeyOverride?.accountKey.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? remote.apiKeyRef?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        finalized.provider = providerKeyOverride?.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            ?? RemoteProviderEndpoints.canonicalBackend(remote.backend)
        finalized.modelID = remote.id.trimmingCharacters(in: .whitespacesAndNewlines)
        finalized.occurredAtMs = occurredAtMs
        finalized.latencyMs = max(0, occurredAtMs - max(0, startedAtMs))
        return finalized
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

    private static func currentTimestampMs() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
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
        timeoutSec: Double,
        providerKeyOverride: ProviderKeyExecutionOverride?
    ) async -> TrialResult {
        var effectiveRemote = remote
        let apiKey = overrideAPIKey(providerKeyOverride, fallback: remote.apiKey)
        if !apiKey.isEmpty {
            effectiveRemote.apiKey = apiKey
        }
        if let baseURL = effectiveBaseURL(remote: remote, providerKeyOverride: providerKeyOverride)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !baseURL.isEmpty {
            effectiveRemote.baseURL = baseURL
        }

        if let providerCallOverride {
            return await providerCallOverride(effectiveRemote, prompt, maxTokens, temperature, topP, timeoutSec)
        }

        switch RemoteProviderEndpoints.canonicalBackend(effectiveRemote.backend) {
        case "anthropic":
            return await performAnthropic(
                remote: effectiveRemote,
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                timeoutSec: timeoutSec,
                providerKeyOverride: providerKeyOverride
            )
        case "gemini":
            return await performGemini(
                remote: effectiveRemote,
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                timeoutSec: timeoutSec,
                providerKeyOverride: providerKeyOverride
            )
        case "remote_catalog":
            var normalizedRemote = effectiveRemote
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
                timeoutSec: timeoutSec,
                providerKeyOverride: providerKeyOverride
            )
        default:
            return await performOpenAICompatible(
                remote: effectiveRemote,
                modelId: providerModelId(for: effectiveRemote),
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                timeoutSec: timeoutSec,
                providerKeyOverride: providerKeyOverride
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
        timeoutSec: Double,
        providerKeyOverride: ProviderKeyExecutionOverride?
    ) async -> TrialResult {
        switch resolvedOpenAIWireAPI(for: remote, providerKeyOverride: providerKeyOverride) {
        case .responses:
            let responseResult = await performOpenAIResponses(
                remote: remote,
                modelId: modelId,
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                timeoutSec: timeoutSec,
                providerKeyOverride: providerKeyOverride
            )
            if shouldFallbackFromResponsesToChatCompletions(
                result: responseResult,
                remote: remote,
                providerKeyOverride: providerKeyOverride
            ) {
                let fallback = await performOpenAIChatCompletions(
                    remote: remote,
                    modelId: modelId,
                    prompt: prompt,
                    maxTokens: maxTokens,
                    temperature: temperature,
                    topP: topP,
                    timeoutSec: timeoutSec,
                    providerKeyOverride: providerKeyOverride
                )
                if fallback.ok {
                    return fallback
                }
            }
            return responseResult
        case .chatCompletions:
            return await performOpenAIChatCompletions(
                remote: remote,
                modelId: modelId,
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                timeoutSec: timeoutSec,
                providerKeyOverride: providerKeyOverride
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
        timeoutSec: Double,
        providerKeyOverride: ProviderKeyExecutionOverride?
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
        applyProviderKeyHeaders(&req, providerKeyOverride: providerKeyOverride)
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
        timeoutSec: Double,
        providerKeyOverride: ProviderKeyExecutionOverride?
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
        applyProviderKeyHeaders(&req, providerKeyOverride: providerKeyOverride)
        req.setValue("RELFlowHub/1.0", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "model": modelId,
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": prompt,
                        ],
                    ],
                ],
            ],
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
        timeoutSec: Double,
        providerKeyOverride: ProviderKeyExecutionOverride?
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
        applyProviderKeyHeaders(&req, providerKeyOverride: providerKeyOverride)
        if req.value(forHTTPHeaderField: "anthropic-version") == nil {
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
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
            let (data, status) = try await send(req)

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
        timeoutSec: Double,
        providerKeyOverride: ProviderKeyExecutionOverride?
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
        applyProviderKeyHeaders(&req, providerKeyOverride: providerKeyOverride)
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
            let (data, status) = try await send(req)

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
