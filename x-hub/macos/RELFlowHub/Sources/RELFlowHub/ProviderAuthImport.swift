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
        var refreshToken: String
        var baseURL: String
        var apiKeyRef: String
        var wireAPI: String
        var authType: String
        var expiresAtMs: Int64
        var email: String
        var accountID: String
        var oauthSourceKey: String
        var authIndex: Int
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
        var imported = try parse(data: data)
        if imported.authIndex <= 0 {
            imported.authIndex = authIndexHint(from: url.lastPathComponent)
        }
        return imported
    }

    static func parse(data: Data) throws -> ImportedCredentials {
        guard let raw = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw ImportError.unsupportedFormat
        }
        let payload = unwrapPayload(raw)
        let env = flattenStringMap(payload)

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
                refreshToken: "",
                baseURL: base,
                apiKeyRef: defaultAPIKeyRef(backend: backend, baseURL: base),
                wireAPI: wireAPI,
                authType: "api_key",
                expiresAtMs: 0,
                email: "",
                accountID: "",
                oauthSourceKey: "",
                authIndex: 0,
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
                refreshToken: "",
                baseURL: base,
                apiKeyRef: defaultAPIKeyRef(backend: backend, baseURL: base),
                wireAPI: "",
                authType: "api_key",
                expiresAtMs: 0,
                email: "",
                accountID: "",
                oauthSourceKey: "",
                authIndex: 0,
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
                refreshToken: "",
                baseURL: base,
                apiKeyRef: defaultAPIKeyRef(backend: backend, baseURL: base),
                wireAPI: "",
                authType: "api_key",
                expiresAtMs: 0,
                email: "",
                accountID: "",
                oauthSourceKey: "",
                authIndex: 0,
                kind: .apiKey
            )
        }

        if let imported = legacyCodexTokenBundle(from: payload, env: env) {
            return imported
        }

        if let imported = providerTokenBundle(from: payload, env: env) {
            return imported
        }

        throw ImportError.noSupportedProviderKey
    }

    private static func legacyCodexTokenBundle(
        from payload: [String: Any],
        env: [String: String]
    ) -> ImportedCredentials? {
        let authMode = nonEmpty(env["auth_mode"])?.lowercased() ?? ""
        let providerHint = resolveProviderHint(payload)
        let tokens = nestedObject(payload, key: "tokens")
        let legacyToken = nestedObject(payload, key: "token")
        let idToken = firstNonEmpty(
            env["id_token"],
            env["idToken"],
            stringValue(tokens?["id_token"]),
            stringValue(legacyToken?["id_token"])
        )
        let refreshToken = firstNonEmpty(
            env["refresh_token"],
            env["refreshToken"],
            stringValue(tokens?["refresh_token"]),
            stringValue(legacyToken?["refresh_token"])
        )
        let accessToken = firstNonEmpty(
            env["access_token"],
            env["accessToken"],
            stringValue(tokens?["access_token"]),
            stringValue(legacyToken?["access_token"])
        )
        let idClaims = decodeJWTPayload(idToken) ?? [:]
        let email = firstNonEmpty(
            env["email"],
            env["account_email"],
            stringValue(payload["email"]),
            stringValue(payload["account_email"]),
            stringValue(idClaims["email"]),
            stringValue(idClaims["preferred_username"])
        )
        let accountID = firstNonEmpty(
            env["account_id"],
            env["accountId"],
            stringValue(payload["account_id"]),
            stringValue(payload["accountId"]),
            stringValue(tokens?["account_id"]),
            stringValue(legacyToken?["account_id"]),
            stringValue(idClaims["chatgpt_account_id"]),
            stringValue(idClaims["account_id"])
        )
        let authIndex = intValue(
            payload["auth_index"]
            ?? payload["authIndex"]
            ?? tokens?["auth_index"]
            ?? legacyToken?["auth_index"]
        )
        let expiresAtMs = parseDateLikeToMs(
            payload["expires_at"]
            ?? payload["expired"]
            ?? tokens?["expiry"]
            ?? legacyToken?["expiry"]
            ?? idClaims["exp"]
        )

        guard !accessToken.isEmpty else { return nil }
        guard authMode == "chatgpt" || providerHint == "codex" else {
            return nil
        }

        let base = firstNonEmpty(
            env["OPENAI_BASE_URL"],
            env["OPENAI_API_BASE"],
            env["OPENAI_BASEURL"],
            env["base_url"],
            env["baseUrl"],
            "https://api.openai.com/v1"
        )
        let backend = "openai"
        return ImportedCredentials(
            backend: backend,
            apiKey: accessToken,
            refreshToken: refreshToken,
            baseURL: base,
            apiKeyRef: defaultAPIKeyRef(backend: backend, baseURL: base),
            // ChatGPT/Codex OAuth bundles often lack `api.responses.write`,
            // but remain compatible with `/v1/chat/completions`.
            wireAPI: RemoteProviderWireAPI.chatCompletions.rawValue,
            authType: refreshToken.isEmpty ? "api_key" : "oauth",
            expiresAtMs: expiresAtMs,
            email: email,
            accountID: accountID,
            oauthSourceKey: "chatgpt",
            authIndex: authIndex,
            kind: .chatGPTTokenBundle
        )
    }

    private struct OAuthProviderDescriptor {
        var backend: String
        var defaultBaseURL: String
        var wireAPI: String
        var oauthSourceKey: String
        var baseEnvKeys: [String]
    }

    private static func providerTokenBundle(
        from payload: [String: Any],
        env: [String: String]
    ) -> ImportedCredentials? {
        let providerHint = resolveProviderHint(payload)
        guard let descriptor = oauthProviderDescriptor(for: providerHint) else {
            return nil
        }

        let tokens = nestedObject(payload, key: "tokens")
        let token = nestedObject(payload, key: "token")
        let idToken = firstNonEmpty(
            env["id_token"],
            env["idToken"],
            stringValue(payload["id_token"]),
            stringValue(token?["id_token"]),
            stringValue(tokens?["id_token"])
        )
        let accessToken = firstNonEmpty(
            env["access_token"],
            env["accessToken"],
            stringValue(payload["access_token"]),
            stringValue(token?["access_token"]),
            stringValue(tokens?["access_token"])
        )
        guard !accessToken.isEmpty else { return nil }

        let refreshToken = firstNonEmpty(
            env["refresh_token"],
            env["refreshToken"],
            stringValue(payload["refresh_token"]),
            stringValue(token?["refresh_token"]),
            stringValue(tokens?["refresh_token"])
        )
        let idClaims = decodeJWTPayload(idToken) ?? [:]
        let email = firstNonEmpty(
            env["email"],
            env["account_email"],
            stringValue(payload["email"]),
            stringValue(token?["email"]),
            stringValue(tokens?["email"]),
            stringValue(idClaims["email"]),
            stringValue(idClaims["preferred_username"])
        )
        let accountID = firstNonEmpty(
            env["account_id"],
            env["accountId"],
            stringValue(payload["account_id"]),
            stringValue(payload["project_id"]),
            stringValue(payload["device_id"]),
            stringValue(token?["account_id"]),
            stringValue(token?["project_id"]),
            stringValue(token?["device_id"]),
            stringValue(tokens?["account_id"]),
            stringValue(tokens?["project_id"]),
            stringValue(tokens?["device_id"]),
            stringValue(idClaims["account_id"])
        )
        let authIndex = intValue(
            payload["auth_index"]
            ?? payload["authIndex"]
            ?? token?["auth_index"]
            ?? tokens?["auth_index"]
        )
        let base = firstNonEmpty(
            in: descriptor.baseEnvKeys.map { env[$0] } + [
                env["base_url"],
                env["baseUrl"],
                stringValue(payload["base_url"]),
                stringValue(payload["baseUrl"]),
                descriptor.defaultBaseURL
            ]
        )
        let expiryCandidates: [Any?] = [
            payload["expires_at"],
            payload["expired"],
            payload["expiry"],
            token?["expires_at"],
            token?["expired"],
            token?["expiry"],
            token?["expires_at_ms"],
            tokens?["expires_at"],
            tokens?["expired"],
            tokens?["expiry"],
            tokens?["expires_at_ms"],
            idClaims["exp"]
        ]
        let expiresAtMs = parseDateLikeToMs(firstNonNil(in: expiryCandidates))

        return ImportedCredentials(
            backend: descriptor.backend,
            apiKey: accessToken,
            refreshToken: refreshToken,
            baseURL: base,
            apiKeyRef: defaultAPIKeyRef(backend: descriptor.backend, baseURL: base),
            wireAPI: descriptor.wireAPI,
            authType: "oauth",
            expiresAtMs: expiresAtMs,
            email: email,
            accountID: accountID,
            oauthSourceKey: descriptor.oauthSourceKey,
            authIndex: authIndex,
            kind: .apiKey
        )
    }

    private static func oauthProviderDescriptor(for providerHint: String) -> OAuthProviderDescriptor? {
        switch providerHint {
        case "claude", "anthropic":
            return OAuthProviderDescriptor(
                backend: "anthropic",
                defaultBaseURL: "https://api.anthropic.com/v1",
                wireAPI: "",
                oauthSourceKey: "claude",
                baseEnvKeys: ["ANTHROPIC_BASE_URL", "ANTHROPIC_API_BASE"]
            )
        case "gemini":
            return OAuthProviderDescriptor(
                backend: "gemini",
                defaultBaseURL: "https://generativelanguage.googleapis.com/v1beta",
                wireAPI: "",
                oauthSourceKey: "gemini",
                baseEnvKeys: ["GEMINI_BASE_URL", "GOOGLE_BASE_URL", "GOOGLE_API_BASE"]
            )
        case "antigravity":
            return OAuthProviderDescriptor(
                backend: "antigravity",
                defaultBaseURL: "https://cloudcode-pa.googleapis.com/v1internal",
                wireAPI: "",
                oauthSourceKey: "antigravity",
                baseEnvKeys: ["ANTIGRAVITY_BASE_URL", "GOOGLE_BASE_URL", "GOOGLE_API_BASE"]
            )
        case "kimi":
            return OAuthProviderDescriptor(
                backend: "kimi",
                defaultBaseURL: "https://api.moonshot.cn/v1",
                wireAPI: "",
                oauthSourceKey: "kimi",
                baseEnvKeys: ["KIMI_BASE_URL", "MOONSHOT_BASE_URL"]
            )
        default:
            return nil
        }
    }

    private static func unwrapPayload(_ raw: [String: Any]) -> [String: Any] {
        if let nested = raw["data"] as? [String: Any] {
            return nested
        }
        return raw
    }

    private static func nestedObject(_ raw: [String: Any], key: String) -> [String: Any]? {
        raw[key] as? [String: Any]
    }

    private static func resolveProviderHint(_ payload: [String: Any]) -> String {
        let candidates = [
            stringValue(payload["provider"]),
            stringValue(payload["type"]),
            stringValue(payload["account_type"]),
            stringValue(payload["accountType"]),
            stringValue(payload["auth_provider"]),
            stringValue(payload["auth_mode"])
        ]
        for candidate in candidates {
            let normalized = normalizedProviderHint(candidate)
            if !normalized.isEmpty {
                return normalized
            }
        }
        return ""
    }

    private static func normalizedProviderHint(_ raw: String?) -> String {
        let value = nonEmpty(raw)?.lowercased() ?? ""
        switch value {
        case "chatgpt", "openai-chatgpt", "codex":
            return "codex"
        case "openai", "openai_compatible", "anthropic", "claude", "gemini", "antigravity", "kimi":
            return value
        case "gemini-cli":
            return "gemini"
        case "google":
            return "gemini"
        case "github-copilot":
            return "copilot"
        default:
            return value
        }
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

    private static func stringValue(_ raw: Any?) -> String? {
        if let string = raw as? String {
            return string
        }
        if let number = raw as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func intValue(_ raw: Any?) -> Int {
        if let value = raw as? Int {
            return value
        }
        if let value = raw as? Int64 {
            return Int(value)
        }
        if let value = raw as? Double {
            return Int(value)
        }
        if let value = raw as? NSNumber {
            return value.intValue
        }
        return 0
    }

    private static func parseDateLikeToMs(_ raw: Any?) -> Int64 {
        if let value = raw as? Int64 {
            return normalizedEpochMs(value)
        }
        if let value = raw as? Int {
            return normalizedEpochMs(Int64(value))
        }
        if let value = raw as? Double {
            return normalizedEpochMs(Int64(value.rounded()))
        }
        guard let text = stringValue(raw) else {
            return 0
        }
        if let numeric = Double(text) {
            return normalizedEpochMs(Int64(numeric.rounded()))
        }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) {
            return Int64((date.timeIntervalSince1970 * 1000.0).rounded())
        }
        return 0
    }

    private static func normalizedEpochMs(_ raw: Int64) -> Int64 {
        guard raw > 0 else { return 0 }
        return raw < 1_000_000_000_000 ? raw * 1000 : raw
    }

    private static func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else {
            return nil
        }
        return decodeBase64URLJSONObject(String(segments[1]))
    }

    private static func decodeBase64URLJSONObject(_ raw: String) -> [String: Any]? {
        var value = raw
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = value.count % 4
        if remainder != 0 {
            value.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: value),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let object = json as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func authIndexHint(from fileName: String) -> Int {
        let lowercased = fileName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lowercased.hasPrefix("auth"), lowercased.hasSuffix(".json") else {
            return 0
        }
        let stem = String(lowercased.dropLast(".json".count))
        let suffix = String(stem.dropFirst("auth".count))
        return Int(suffix) ?? 0
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

    private static func firstNonEmpty(in values: [String?]) -> String {
        for value in values {
            if let normalized = nonEmpty(value) {
                return normalized
            }
        }
        return ""
    }

    private static func firstNonNil(in values: [Any?]) -> Any? {
        for value in values where value != nil {
            return value
        }
        return nil
    }
}
