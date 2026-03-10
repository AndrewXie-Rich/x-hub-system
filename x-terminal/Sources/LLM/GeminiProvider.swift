import Foundation

final class GeminiProvider: LLMProvider {
    let displayName = "Gemini"

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
                continuation.finish(throwing: NSError(domain: "xterminal", code: 401, userInfo: [NSLocalizedDescriptionKey: "Gemini API key is empty. Open Settings and set Gemini key."]))
            }
        }

        // Generative Language API (v1beta).
        // POST /v1beta/models/{model}:streamGenerateContent?key=...
        // Build as a single path string so the ':' is not percent-escaped.
        let base = baseURL.absoluteString.hasSuffix("/") ? baseURL.absoluteString : (baseURL.absoluteString + "/")
        let path = "v1beta/models/\(model):streamGenerateContent"
        let url = URL(string: base + path) ?? baseURL

        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = comps?.queryItems ?? []
        items.append(URLQueryItem(name: "key", value: k))
        comps?.queryItems = items
        let finalURL = comps?.url ?? url

        let userText = req.messages.map { $0.content }.joined(separator: "\n\n")
        let payload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": userText]],
                ],
            ],
            "generationConfig": [
                "temperature": req.temperature,
                "topP": req.topP,
                "maxOutputTokens": req.maxTokens,
            ],
        ]

        var request = URLRequest(url: finalURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse {
                        if http.statusCode < 200 || http.statusCode >= 300 {
                            let body = try await bytes.collectString(limit: 20_000)
                            throw NSError(domain: "xterminal", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Gemini HTTP \(http.statusCode): \(body)"])
                        }
                    }

                    // v1beta streaming returns JSON objects separated by newlines.
                    // We'll parse each line as an independent JSON chunk.
                    for try await line in bytes.lines {
                        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if s.isEmpty { continue }
                        guard let data = s.data(using: .utf8) else { continue }
                        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                        if let candidates = obj["candidates"] as? [[String: Any]],
                           let c0 = candidates.first,
                           let content = c0["content"] as? [String: Any],
                           let parts = content["parts"] as? [[String: Any]] {
                            for p in parts {
                                if let t = p["text"] as? String, !t.isEmpty {
                                    continuation.yield(.delta(t))
                                }
                            }
                        }
                    }

                    continuation.yield(.done(ok: true, reason: "eos", usage: nil))
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
