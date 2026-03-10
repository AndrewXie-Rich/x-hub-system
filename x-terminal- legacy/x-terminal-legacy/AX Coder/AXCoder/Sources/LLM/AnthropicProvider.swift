import Foundation

final class AnthropicProvider: LLMProvider {
    let displayName = "Claude"

    private let baseURL: URL
    private let apiKey: String
    private let model: String

    init(baseURL: URL, apiKey: String, model: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }

    func stream(_ req: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let k = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.isEmpty {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NSError(domain: "xterminal", code: 401, userInfo: [NSLocalizedDescriptionKey: "Anthropic API key is empty. Open Settings and set Claude key."]))
            }
        }

        let url = baseURL.appendingPathComponent("v1/messages")

        // Anthropic messages API: role user/assistant, content blocks.
        let userText = req.messages.map { $0.content }.joined(separator: "\n\n")
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": req.maxTokens,
            "temperature": req.temperature,
            "top_p": req.topP,
            "stream": true,
            "messages": [
                ["role": "user", "content": [["type": "text", "text": userText]]],
            ],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(k, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse {
                        if http.statusCode < 200 || http.statusCode >= 300 {
                            let body = try await bytes.collectString(limit: 20_000)
                            throw NSError(domain: "xterminal", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Anthropic HTTP \(http.statusCode): \(body)"])
                        }
                    }

                    var usage: LLMUsage? = nil
                    var currentEvent: String = ""
                    var currentData: String = ""

                    func flushEvent() {
                        let ev = currentEvent
                        let dataStr = currentData
                        currentEvent = ""
                        currentData = ""
                        guard !dataStr.isEmpty else { return }
                        guard let data = dataStr.data(using: .utf8) else { return }
                        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

                        // content_block_delta: delta.text
                        if ev == "content_block_delta" {
                            if let delta = obj["delta"] as? [String: Any], let text = delta["text"] as? String, !text.isEmpty {
                                continuation.yield(.delta(text))
                            }
                        }

                        // message_start sometimes contains usage.
                        if ev == "message_start" {
                            if let msg = obj["message"] as? [String: Any], let u = msg["usage"] as? [String: Any] {
                                let pt = (u["input_tokens"] as? Int) ?? 0
                                let ct = (u["output_tokens"] as? Int) ?? 0
                                if pt > 0 || ct > 0 {
                                    usage = LLMUsage(promptTokens: pt, completionTokens: ct)
                                }
                            }
                        }

                        if ev == "message_delta" {
                            if let u = obj["usage"] as? [String: Any] {
                                let pt = (u["input_tokens"] as? Int) ?? 0
                                let ct = (u["output_tokens"] as? Int) ?? 0
                                if pt > 0 || ct > 0 {
                                    usage = LLMUsage(promptTokens: pt, completionTokens: ct)
                                }
                            }
                        }
                    }

                    for try await line in bytes.lines {
                        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if s.isEmpty {
                            flushEvent()
                            continue
                        }
                        if s.hasPrefix("event:") {
                            currentEvent = s.dropFirst(6).trimmingCharacters(in: .whitespacesAndNewlines)
                            continue
                        }
                        if s.hasPrefix("data:") {
                            let payloadLine = s.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                            if currentData.isEmpty {
                                currentData = payloadLine
                            } else {
                                currentData += "\n" + payloadLine
                            }
                            continue
                        }
                    }
                    flushEvent()

                    continuation.yield(.done(ok: true, reason: "eos", usage: usage))
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
