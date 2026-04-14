import Foundation
import RELFlowHubCore

enum ProviderAuthImport {
    enum CredentialKind: String, Equatable {
        case apiKey
        case chatGPTTokenBundle = "chatgpt_token_bundle"
    }

    struct ImportedCredentials: Equatable {
        var backend: String
        var apiKey: String
        var baseURL: String
        var apiKeyRef: String
        var wireAPI: String
        var kind: CredentialKind
    }

    enum ImportError: LocalizedError {
        case unsupportedFormat
        case noSupportedProviderKey

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return HubUIStrings.Models.ProviderImport.authUnsupportedFormat
            case .noSupportedProviderKey:
                return HubUIStrings.Models.ProviderImport.authNoSupportedProviderKey
            }
        }
    }

    static func load(from url: URL) throws -> ImportedCredentials {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> ImportedCredentials {
        guard let raw = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw ImportError.unsupportedFormat
        }
        let env = flattenStringMap(raw)

        if let key = nonEmpty(env["OPENAI_API_KEY"]) {
            let base = firstNonEmpty(
                env["OPENAI_BASE_URL"],
                env["OPENAI_API_BASE"],
                env["OPENAI_BASEURL"]
            )
            let wireAPI = firstNonEmpty(
                env["OPENAI_WIRE_API"],
                env["WIRE_API"],
                env["wire_api"]
            )
            let backend = inferredOpenAIBackend(baseURL: base)
            return ImportedCredentials(
                backend: backend,
                apiKey: key,
                baseURL: base,
                apiKeyRef: defaultAPIKeyRef(backend: backend, baseURL: base),
                wireAPI: wireAPI,
                kind: .apiKey
            )
        }

        if let key = nonEmpty(env["ANTHROPIC_API_KEY"]) {
            let base = firstNonEmpty(
                env["ANTHROPIC_BASE_URL"],
                env["ANTHROPIC_API_BASE"]
            )
            let backend = "anthropic"
            return ImportedCredentials(
                backend: backend,
                apiKey: key,
                baseURL: base,
                apiKeyRef: defaultAPIKeyRef(backend: backend, baseURL: base),
                wireAPI: "",
                kind: .apiKey
            )
        }

        if let key = nonEmpty(env["GEMINI_API_KEY"]) ?? nonEmpty(env["GOOGLE_API_KEY"]) {
            let base = firstNonEmpty(
                env["GEMINI_BASE_URL"],
                env["GOOGLE_BASE_URL"],
                env["GOOGLE_API_BASE"]
            )
            let backend = "gemini"
            return ImportedCredentials(
                backend: backend,
                apiKey: key,
                baseURL: base,
                apiKeyRef: defaultAPIKeyRef(backend: backend, baseURL: base),
                wireAPI: "",
                kind: .apiKey
            )
        }

        let authMode = nonEmpty(env["auth_mode"])?.lowercased() ?? ""
        if authMode == "chatgpt",
           let tokens = raw["tokens"] as? [String: Any],
           let accessToken = nonEmpty(tokens["access_token"] as? String) {
            let base = firstNonEmpty(
                env["OPENAI_BASE_URL"],
                env["OPENAI_API_BASE"],
                env["OPENAI_BASEURL"],
                "https://api.openai.com/v1"
            )
            let backend = "openai"
            return ImportedCredentials(
                backend: backend,
                apiKey: accessToken,
                baseURL: base,
                apiKeyRef: defaultAPIKeyRef(backend: backend, baseURL: base),
                wireAPI: RemoteProviderWireAPI.responses.rawValue,
                kind: .chatGPTTokenBundle
            )
        }

        throw ImportError.noSupportedProviderKey
    }

    private static func flattenStringMap(_ raw: [String: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in raw {
            if let string = value as? String {
                out[key] = string
                continue
            }
            if let number = value as? NSNumber {
                out[key] = number.stringValue
            }
        }
        return out
    }

    private static func inferredOpenAIBackend(baseURL: String) -> String {
        guard let host = URL(string: baseURL)?.host?.lowercased(), !host.isEmpty else {
            return "openai"
        }
        if host.contains("openai.com") {
            return "openai"
        }
        return "openai_compatible"
    }

    private static func defaultAPIKeyRef(backend: String, baseURL: String) -> String {
        let canonical = RemoteProviderEndpoints.canonicalBackend(backend)
        if let host = URL(string: baseURL)?.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
            return "\(canonical):\(host)"
        }
        switch canonical {
        case "openai":
            return "openai:api.openai.com"
        case "openai_compatible":
            return "openai_compatible:default"
        case "anthropic":
            return "anthropic:api.anthropic.com"
        case "gemini":
            return "gemini:generativelanguage.googleapis.com"
        case "remote_catalog":
            return "remote_catalog:default"
        default:
            return canonical.isEmpty ? UUID().uuidString : canonical
        }
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func firstNonEmpty(_ values: String?...) -> String {
        for value in values {
            if let normalized = nonEmpty(value) {
                return normalized
            }
        }
        return ""
    }
}
