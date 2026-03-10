import Foundation

public enum RemoteProviderEndpoints {
    public static func normalizedBackend(_ backend: String) -> String {
        backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func openAIChatCompletionsURL(baseURL: String?, backend: String) -> URL? {
        let b = normalizedBackend(backend)
        let base = normalizedBase(baseURL)
        if base.isEmpty {
            if b == "openai" {
                return URL(string: "https://api.openai.com/v1/chat/completions")
            }
            if b == "opencode" || b == "opencode_zen" {
                return URL(string: "https://opencode.ai/zen/v1/chat/completions")
            }
            return nil
        }
        if base.hasSuffix("/chat/completions") {
            return URL(string: base)
        }
        if base.hasSuffix("/v1") {
            return URL(string: base + "/chat/completions")
        }
        return URL(string: base + "/v1/chat/completions")
    }

    public static func openAIModelsURL(baseURL: String?, backend: String) -> URL? {
        let b = normalizedBackend(backend)
        let base = normalizedBase(baseURL)
        if base.isEmpty {
            if b == "openai" {
                return URL(string: "https://api.openai.com/v1/models")
            }
            if b == "opencode" || b == "opencode_zen" {
                return URL(string: "https://opencode.ai/zen/v1/models")
            }
            return nil
        }
        if base.hasSuffix("/models") {
            return URL(string: base)
        }
        if base.hasSuffix("/v1") {
            return URL(string: base + "/models")
        }
        return URL(string: base + "/v1/models")
    }

    public static func anthropicMessagesURL(baseURL: String?) -> URL? {
        let base = normalizedBase(baseURL)
        if base.isEmpty {
            return URL(string: "https://api.anthropic.com/v1/messages")
        }
        if base.hasSuffix("/messages") {
            return URL(string: base)
        }
        if base.hasSuffix("/models") {
            let s = String(base.dropLast("/models".count))
            return URL(string: s + "/messages")
        }
        if base.hasSuffix("/v1") {
            return URL(string: base + "/messages")
        }
        return URL(string: base + "/v1/messages")
    }

    public static func anthropicModelsURL(baseURL: String?) -> URL? {
        let base = normalizedBase(baseURL)
        if base.isEmpty {
            return URL(string: "https://api.anthropic.com/v1/models")
        }
        if base.hasSuffix("/models") {
            return URL(string: base)
        }
        if base.hasSuffix("/messages") {
            let s = String(base.dropLast("/messages".count))
            return URL(string: s + "/models")
        }
        if base.hasSuffix("/v1") {
            return URL(string: base + "/models")
        }
        return URL(string: base + "/v1/models")
    }

    public static func geminiGenerateURL(baseURL: String?, modelId: String, apiKey: String?) -> URL? {
        let model = normalizedGeminiModelId(modelId)
        let base = normalizedBase(baseURL)
        let raw: String
        if base.isEmpty {
            raw = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        } else if base.contains("{model}") {
            raw = base.replacingOccurrences(of: "{model}", with: model)
        } else if base.hasSuffix(":generateContent") {
            raw = base
        } else if base.hasSuffix("/v1beta") {
            raw = base + "/models/\(model):generateContent"
        } else {
            raw = base + "/v1beta/models/\(model):generateContent"
        }
        return appendAPIKey(rawURL: raw, apiKey: apiKey)
    }

    public static func geminiModelsURL(baseURL: String?, apiKey: String?) -> URL? {
        let base = normalizedBase(baseURL)
        let raw: String
        if base.isEmpty {
            raw = "https://generativelanguage.googleapis.com/v1beta/models"
        } else if base.hasSuffix("/models") {
            raw = base
        } else if base.hasSuffix("/v1beta") {
            raw = base + "/models"
        } else {
            raw = base + "/v1beta/models"
        }
        return appendAPIKey(rawURL: raw, apiKey: apiKey)
    }

    public static func normalizedGeminiModelId(_ raw: String) -> String {
        let stripped = stripModelRef(raw)
        return stripped.isEmpty ? "gemini-1.5-pro" : stripped
    }

    public static func stripModelRef(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("models/") {
            s = String(s.dropFirst("models/".count))
        }
        if let idx = s.lastIndex(of: "/") {
            s = String(s[s.index(after: idx)...])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedBase(_ raw: String?) -> String {
        var base = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return base
    }

    private static func appendAPIKey(rawURL: String, apiKey: String?) -> URL? {
        let key = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return URL(string: rawURL)
        }
        guard var comps = URLComponents(string: rawURL) else {
            return URL(string: rawURL)
        }
        var items = comps.queryItems ?? []
        items.removeAll { $0.name == "key" }
        items.append(URLQueryItem(name: "key", value: key))
        comps.queryItems = items
        return comps.url
    }
}
