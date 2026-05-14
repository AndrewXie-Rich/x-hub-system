import Foundation

// Minimal OpenAI-compatible Chat Completions streaming provider.
// Works with OpenAI and many OpenAI-compatible gateways when configured.
final class OpenAICompatibleProvider: LLMProvider {
    let displayName: String

    private let baseURL: URL
    private let apiKey: String
    private let model: String
    private let useProviderKeyPool: Bool

    init(baseURL: URL, apiKey: String, model: String, displayName: String = "OpenAI-compatible", useProviderKeyPool: Bool = false) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.useProviderKeyPool = useProviderKeyPool
        if displayName != "OpenAI-compatible" {
            self.displayName = displayName
        } else {
            let host = (baseURL.host ?? "").lowercased()
            if host.contains("openai") {
                self.displayName = "OpenAI"
            } else {
                self.displayName = "API"
            }
        }
    }

    func stream(_ req: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        if useProviderKeyPool {
            return streamWithProviderKeyPool(req)
        }
        return streamDirect(req)
    }

    private func streamDirect(_ req: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let k = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.isEmpty {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NSError(domain: "xterminal", code: 401, userInfo: [NSLocalizedDescriptionKey: "OpenAI-compatible API key is empty. Open Settings -> OpenAI-Compatible and set API Key."]))
            }
        }
        return makeStream(req: req, effectiveApiKey: k, effectiveBaseURL: baseURL, accountKey: nil)
    }

    private func streamWithProviderKeyPool(_ req: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let account = await ProviderKeyManager.shared.resolveProviderKey(forModelId: self.model)
                let effectiveApiKey = self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let effectiveBaseURL: URL
                let accountKey: String?

                if let account = account {
                    if !account.baseUrl.isEmpty, let url = URL(string: account.baseUrl) {
                        effectiveBaseURL = url
                    } else {
                        effectiveBaseURL = self.baseURL
                    }
                    if ProviderKeyRuntimeFeedbackSupport.matchesRedactedKey(
                        effectiveApiKey,
                        redacted: account.apiKeyRedacted
                    ) {
                        accountKey = account.accountKey
                    } else {
                        accountKey = nil
                    }
                } else {
                    effectiveBaseURL = self.baseURL
                    accountKey = nil
                }

                if effectiveApiKey.isEmpty {
                    continuation.finish(throwing: NSError(
                        domain: "xterminal",
                        code: 401,
                        userInfo: [
                            NSLocalizedDescriptionKey: "No executable API key available. Hub key pools do not expose raw secrets to XT direct providers; use a local API key or route this model through Hub."
                        ]
                    ))
                    return
                }

                let innerStream = self.makeStream(req: req, effectiveApiKey: effectiveApiKey, effectiveBaseURL: effectiveBaseURL, accountKey: accountKey)
                do {
                    for try await event in innerStream {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func makeStream(req: LLMRequest, effectiveApiKey: String, effectiveBaseURL: URL, accountKey: String?) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let url = effectiveBaseURL.appendingPathComponent("v1/chat/completions")

        let payload: [String: Any] = [
            "model": model,
            "stream": true,
            // Ask for usage in stream when supported.
            "stream_options": ["include_usage": true],
            "temperature": req.temperature,
            "top_p": req.topP,
            "max_tokens": req.maxTokens,
            "messages": req.messages.map { ["role": $0.role, "content": $0.content] },
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(effectiveApiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])

        return AsyncThrowingStream { continuation in
            Task {
                let startedAtMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse {
                        if http.statusCode < 200 || http.statusCode >= 300 {
                            let body = try await bytes.collectString(limit: 20_000)
                            throw NSError(domain: "xterminal", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "OpenAI API HTTP \(http.statusCode): \(body)"])
                        }
                    }

                    var usage: LLMUsage? = nil

                    for try await line in bytes.lines {
                        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if s.isEmpty { continue }
                        if !s.hasPrefix("data:") { continue }
                        let dataStr = s.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                        if dataStr == "[DONE]" {
                            if let accountKey = accountKey {
                                let totalTokens = Int64((usage?.promptTokens ?? 0) + (usage?.completionTokens ?? 0))
                                await ProviderKeyManager.shared.reportUsage(
                                    accountKey: accountKey,
                                    modelID: self.model,
                                    tokensUsed: totalTokens,
                                    costUsd: 0,
                                    latencyMs: max(0, Int64((Date().timeIntervalSince1970 * 1000.0).rounded()) - startedAtMs),
                                    occurredAtMs: Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
                                )
                            }
                            continuation.yield(.done(ok: true, reason: "eos", usage: usage))
                            continuation.finish()
                            return
                        }
                        guard let data = dataStr.data(using: .utf8) else { continue }
                        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                        // choices[0].delta.content
                        if let choices = obj["choices"] as? [[String: Any]],
                           let delta = choices.first?["delta"] as? [String: Any],
                           let content = delta["content"] as? String {
                            if !content.isEmpty {
                                continuation.yield(.delta(content))
                            }
                        }

                        // usage can appear in the final streamed chunk if include_usage is supported.
                        if let u = obj["usage"] as? [String: Any] {
                            let pt = (u["prompt_tokens"] as? Int) ?? 0
                            let ct = (u["completion_tokens"] as? Int) ?? 0
                            if pt > 0 || ct > 0 {
                                usage = LLMUsage(promptTokens: pt, completionTokens: ct)
                            }
                        }
                    }

                    if let accountKey = accountKey {
                        let streamEndedError = NSError(
                            domain: "xterminal",
                            code: 0,
                            userInfo: [NSLocalizedDescriptionKey: "stream_ended"]
                        )
                        _ = await ProviderKeyManager.shared.reportError(
                            accountKey: accountKey,
                            modelID: self.model,
                            error: streamEndedError,
                            latencyMs: max(0, Int64((Date().timeIntervalSince1970 * 1000.0).rounded()) - startedAtMs),
                            occurredAtMs: Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
                        )
                    }
                    continuation.yield(.done(ok: false, reason: "stream_ended", usage: usage))
                    continuation.finish()
                } catch {
                    if let accountKey = accountKey {
                        _ = await ProviderKeyManager.shared.reportError(
                            accountKey: accountKey,
                            modelID: self.model,
                            error: error,
                            latencyMs: max(0, Int64((Date().timeIntervalSince1970 * 1000.0).rounded()) - startedAtMs),
                            occurredAtMs: Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
                        )
                    }
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private extension URLSession.AsyncBytes {
    func collectString(limit: Int) async throws -> String {
        var out = ""
        out.reserveCapacity(Swift.min(limit, 4096))
        for try await line in self.lines {
            out += line
            out += "\n"
            if out.count >= limit { break }
        }
        return out
    }
}
