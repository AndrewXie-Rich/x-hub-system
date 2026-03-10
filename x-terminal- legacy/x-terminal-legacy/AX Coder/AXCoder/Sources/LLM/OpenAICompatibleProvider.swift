import Foundation

// Minimal OpenAI-compatible Chat Completions streaming provider.
// Works with OpenAI and many OpenAI-compatible gateways when configured.
final class OpenAICompatibleProvider: LLMProvider {
    let displayName: String

    private let baseURL: URL
    private let apiKey: String
    private let model: String

    init(baseURL: URL, apiKey: String, model: String, displayName: String = "OpenAI-compatible") {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
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
        let k = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.isEmpty {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NSError(domain: "xterminal", code: 401, userInfo: [NSLocalizedDescriptionKey: "OpenAI-compatible API key is empty. Open Settings -> OpenAI-Compatible and set API Key."]))
            }
        }
        let url = baseURL.appendingPathComponent("v1/chat/completions")

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
        request.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])

        return AsyncThrowingStream { continuation in
            Task {
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

                    continuation.yield(.done(ok: false, reason: "stream_ended", usage: usage))
                    continuation.finish()
                } catch {
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
